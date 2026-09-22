import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../database/prisma.service";
import { ApiErrorException } from "../http/api-error";
import type { SeedInstrument } from "./instruments";
import type {
  MarketInterval,
  ProviderCandleSeries,
} from "./market-data.provider";

const symbols: Record<string, string> = {
  aapl: "AAPL",
  msft: "MSFT",
  nvda: "NVDA",
  spx: "SPX",
  ndx: "NDX",
  "xau-usd": "XAU/USD",
  "xag-usd": "XAG/USD",
};
const sampleMs = 15 * 60_000;
const retentionMs = 30 * 24 * 60 * 60_000;
const intervalMs: Record<MarketInterval, number> = {
  "1m": 60_000,
  "5m": 300_000,
  "15m": sampleMs,
  "30m": 1_800_000,
  "1h": 3_600_000,
  "4h": 14_400_000,
  "1d": 86_400_000,
  "1w": 604_800_000,
  "1M": 2_592_000_000,
};

@Injectable()
export class SampledPriceService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SampledPriceService.name);
  private timer?: NodeJS.Timeout;
  private busy = false;
  private readonly attemptedBuckets = new Map<string, number>();
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  get enabled() {
    return (
      Boolean(this.config.get<string>("TWELVE_DATA_API_KEY")?.trim()) &&
      this.config.get<string>("TWELVE_DATA_EXTERNAL_DISPLAY_APPROVED") ===
        "true"
    );
  }
  supports(id: string) {
    return Object.hasOwn(symbols, id);
  }

  onModuleInit() {
    void this.poll();
    this.timer = setInterval(() => void this.poll(), 60_000);
    this.timer.unref();
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  async poll(now = new Date()) {
    if (this.busy) return;
    this.busy = true;
    try {
      const cutoff = new Date(now.getTime() - retentionMs);
      await this.prisma.sampledPrice.deleteMany({
        where: { sampledAt: { lte: cutoff } },
      });
      if (!this.enabled) return;
      const bucketTime = new Date(
        Math.floor(now.getTime() / sampleMs) * sampleMs,
      );
      const key = this.config.get<string>("TWELVE_DATA_API_KEY")!.trim();
      for (const [instrumentSlug, symbol] of Object.entries(symbols)) {
        if (this.attemptedBuckets.get(instrumentSlug) === bucketTime.getTime())
          continue;
        const existing = await this.prisma.sampledPrice.findFirst({
          where: { instrumentSlug, sampledAt: { gte: bucketTime } },
        });
        if (existing) continue;
        this.attemptedBuckets.set(instrumentSlug, bucketTime.getTime());
        try {
          const response = await fetch(
            `https://api.twelvedata.com/price?symbol=${encodeURIComponent(symbol)}`,
            {
              headers: {
                Authorization: `apikey ${key}`,
                Accept: "application/json",
              },
              signal: AbortSignal.timeout(8_000),
            },
          );
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          const body = (await response.json()) as {
            price?: unknown;
            status?: unknown;
            message?: unknown;
          };
          if (
            typeof body.price !== "string" ||
            !/^\d+(?:\.\d+)?$/.test(body.price)
          )
            throw new Error("Provider returned no valid price");
          const price = new Prisma.Decimal(body.price);
          if (!price.isFinite() || price.lessThanOrEqualTo(0))
            throw new Error("Provider returned invalid price");
          await this.prisma.sampledPrice.create({
            data: {
              instrumentSlug,
              price,
              sampledAt: now,
              provider: "TWELVE_DATA_PRICE",
            },
          });
        } catch (error) {
          this.logger.warn(
            `Price sample unavailable for ${instrumentSlug}: ${error instanceof Error ? error.message : "unknown error"}`,
          );
        }
      }
    } catch (error) {
      this.logger.error("Price sample retention or polling failed", error);
    } finally {
      this.busy = false;
    }
  }

  async candles(
    instrument: SeedInstrument,
    timeframe: MarketInterval,
    limit: number,
    before?: Date,
  ): Promise<ProviderCandleSeries> {
    const effectiveInterval =
      intervalMs[timeframe] < sampleMs ? "15m" : timeframe;
    const bucketMs = intervalMs[effectiveInterval];
    const rows = await this.prisma.sampledPrice.findMany({
      where: {
        instrumentSlug: instrument.id,
        sampledAt: {
          gt: new Date(Date.now() - retentionMs),
          ...(before ? { lt: before } : {}),
        },
      },
      orderBy: [{ sampledAt: "desc" }, { id: "desc" }],
      take: 3000,
    });
    if (!rows.length)
      throw new ApiErrorException(
        "MARKET_PRICE_NOT_READY",
        "Real price samples are not available yet for this instrument.",
        503,
      );
    const buckets = new Map<number, typeof rows>();
    for (const row of rows.reverse()) {
      const start = Math.floor(row.sampledAt.getTime() / bucketMs) * bucketMs;
      const group = buckets.get(start) ?? [];
      group.push(row);
      buckets.set(start, group);
    }
    const candles = [...buckets.entries()]
      .slice(-limit)
      .map(([start, samples]) => ({
        openTime: new Date(start).toISOString(),
        closeTime: new Date(start + bucketMs).toISOString(),
        open: samples[0]!.price.toString(),
        high: Prisma.Decimal.max(
          ...samples.map((sample) => sample.price),
        ).toString(),
        low: Prisma.Decimal.min(
          ...samples.map((sample) => sample.price),
        ).toString(),
        close: samples.at(-1)!.price.toString(),
        volume: null,
      }));
    return {
      providerId: "TWELVE_DATA_PRICE",
      provider: "Twelve Data sampled price",
      sourceSymbol: symbols[instrument.id]!,
      effectiveInterval,
      freshness: "SAMPLED",
      providerTimestamp: rows.at(-1)!.sampledAt.toISOString(),
      isSyntheticOhlc: true,
      candles,
    };
  }
}
