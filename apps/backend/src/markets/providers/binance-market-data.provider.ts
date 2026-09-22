import { Injectable } from "@nestjs/common";
import type { SeedInstrument } from "../instruments";
import type {
  Candle,
  MarketInterval,
  ProviderCandleSeries,
} from "../market-data.provider";
import { HttpMarketDataProvider } from "./http-market-data.provider";

@Injectable()
export class BinanceMarketDataProvider extends HttpMarketDataProvider {
  readonly id = "BINANCE_PUBLIC_SPOT";
  readonly name = "Binance Public Spot";

  supports(instrument: SeedInstrument): boolean {
    return instrument.assetClass === "CRYPTO";
  }

  async getCandles(
    instrument: SeedInstrument,
    timeframe: MarketInterval,
    limit: number,
    before?: Date,
  ): Promise<ProviderCandleSeries> {
    const sourceSymbol = `${instrument.baseAsset}${
      instrument.quoteAsset === "USD" ? "USDT" : instrument.quoteAsset
    }`;
    const query = new URLSearchParams({
      symbol: sourceSymbol,
      interval: timeframe,
      limit: String(limit),
    });
    if (before) query.set("endTime", String(before.getTime() - 1));
    const payload = await this.fetchJson<unknown>(
      `https://api.binance.com/api/v3/klines?${query.toString()}`,
    );
    if (!Array.isArray(payload)) this.invalidResponse();
    const candles: Candle[] = payload.map((row) => {
      if (!Array.isArray(row) || row.length < 7) this.invalidResponse();
      const openTime = this.isoTimestamp(row[0]);
      const closeTime = this.isoTimestamp(row[6]);
      if (!row.slice(1, 6).every((value) => this.isDecimal(value))) {
        this.invalidResponse();
      }
      return {
        openTime,
        closeTime,
        open: String(row[1]),
        high: String(row[2]),
        low: String(row[3]),
        close: String(row[4]),
        volume: String(row[5]),
      };
    });
    if (candles.length === 0) this.invalidResponse();
    return {
      providerId: this.id,
      provider: this.name,
      sourceSymbol,
      effectiveInterval: timeframe,
      freshness: "DISPLAY_LIVE",
      providerTimestamp: candles.at(-1)!.closeTime,
      isSyntheticOhlc: false,
      candles,
    };
  }

  private isoTimestamp(value: unknown): string {
    const date = new Date(Number(value));
    if (!Number.isFinite(date.getTime())) this.invalidResponse();
    return date.toISOString();
  }

  private isDecimal(value: unknown): boolean {
    return typeof value === "string" && /^\d+(?:\.\d+)?$/.test(value);
  }
}
