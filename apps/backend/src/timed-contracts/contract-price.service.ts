import { Injectable, Optional } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { ApiErrorException } from "../http/api-error";
import { PrismaService } from "../database/prisma.service";

type Observation = {
  price: Prisma.Decimal;
  timestamp: Date;
  providerId: string;
};

@Injectable()
export class ContractPriceService {
  private readonly inFlight = new Map<string, Promise<Observation>>();
  constructor(@Optional() private readonly prisma?: PrismaService) {}
  async at(
    instrument: { baseAsset: string; assetClass: string },
    boundary: Date,
  ) {
    if (instrument.assetClass !== "CRYPTO") {
      throw new ApiErrorException(
        "CONTRACT_PRICE_UNAVAILABLE",
        "This instrument has no configured contract price source.",
        503,
      );
    }
    const symbol = `${instrument.baseAsset}USDT`;
    if (!/^[A-Z0-9]+USDT$/.test(symbol))
      throw new Error("Invalid contract symbol");
    // Last fully closed UTC second before the contract boundary; never a later price.
    const start = Math.floor(boundary.getTime() / 1000) * 1000 - 1000;
    const providerId = `BINANCE_1S_V1:${symbol}`;
    const key = `${providerId}:${start}`;
    const existing = this.inFlight.get(key);
    if (existing) return existing;
    if (this.inFlight.size >= 100) {
      throw new ApiErrorException(
        "CONTRACT_PRICE_UNAVAILABLE",
        "Price service is busy. Please retry.",
        503,
      );
    }
    const pending = this.load(symbol, providerId, start);
    this.inFlight.set(key, pending);
    try {
      return await pending;
    } finally {
      this.inFlight.delete(key);
    }
  }

  private async load(
    symbol: string,
    providerId: string,
    start: number,
  ): Promise<Observation> {
    const timestamp = new Date(start + 999);
    const archived = await this.prisma?.contractPriceObservation.findUnique({
      where: { source_timestamp: { source: providerId, timestamp } },
    });
    if (archived) return { price: archived.price, timestamp, providerId };
    const query = new URLSearchParams({
      symbol,
      interval: "1s",
      startTime: String(start),
      endTime: String(start + 999),
      limit: "1",
    });
    try {
      let response = await fetch(
        `https://api.binance.com/api/v3/klines?${query.toString()}`,
        { signal: AbortSignal.timeout(4000) },
      );
      if (!response.ok) throw new Error("Provider unavailable");
      let payload: unknown = await response.json();
      if (Array.isArray(payload) && payload.length === 0) {
        await new Promise((resolve) => setTimeout(resolve, 500));
        response = await fetch(
          `https://api.binance.com/api/v3/klines?${query.toString()}`,
          { signal: AbortSignal.timeout(1500) },
        );
        if (!response.ok) throw new Error("Provider unavailable");
        payload = await response.json();
      }
      if (!Array.isArray(payload) || payload.length !== 1)
        throw new Error("Missing observation");
      const row: unknown = payload[0];
      if (
        !Array.isArray(row) ||
        row[0] !== start ||
        row[6] !== start + 999 ||
        typeof row[4] !== "string"
      )
        throw new Error("Wrong observation");
      const price = new Prisma.Decimal(row[4]);
      if (!price.isFinite() || price.lessThanOrEqualTo(0))
        throw new Error("Invalid price");
      if (this.prisma) {
        await this.prisma.contractPriceObservation.createMany({
          data: [
            {
              source: providerId,
              timestamp,
              price,
              payload: row as Prisma.InputJsonValue,
            },
          ],
          skipDuplicates: true,
        });
        const saved =
          await this.prisma.contractPriceObservation.findUniqueOrThrow({
            where: { source_timestamp: { source: providerId, timestamp } },
          });
        return { price: saved.price, timestamp, providerId };
      }
      return {
        price,
        timestamp,
        providerId,
      };
    } catch {
      throw new ApiErrorException(
        "CONTRACT_PRICE_UNAVAILABLE",
        "The required price observation is unavailable. Settlement will remain pending.",
        503,
      );
    }
  }
}
