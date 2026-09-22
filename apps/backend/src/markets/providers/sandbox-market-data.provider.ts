import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { SeedInstrument } from "../instruments";
import { type MarketInterval, type ProviderCandleSeries, type Candle } from "../market-data.provider";
import { HttpMarketDataProvider } from "./http-market-data.provider";
import { DemoPriceService } from "../../trading/demo-price.service";

const intervals: Record<MarketInterval, number> = {
  "1m": 60_000, "5m": 300_000, "15m": 900_000, "30m": 1_800_000,
  "1h": 3_600_000, "4h": 14_400_000, "1d": 86_400_000,
  "1w": 604_800_000, "1M": 2_592_000_000,
};

/** Display-only, deterministic paper candles. Never a licensed or live feed. */
@Injectable()
export class SandboxMarketDataProvider extends HttpMarketDataProvider {
  readonly id = "PRIMEVEST_SANDBOX";
  readonly name = "Simulated virtual-market chart";
  constructor(private readonly prices: DemoPriceService) { super(); }
  supports(instrument: SeedInstrument) { return instrument.assetClass !== "CRYPTO"; }
  async getCandles(instrument: SeedInstrument, timeframe: MarketInterval, limit: number, before?: Date): Promise<ProviderCandleSeries> {
    const duration = intervals[timeframe];
    const cutoff = Math.min(before?.getTime() ?? Date.now(), Date.now());
    const lastOpen = Math.floor((cutoff - 1) / duration) * duration;
    const mark = (time: number) => this.prices.mark({ slug: instrument.id, pricePrecision: instrument.pricePrecision }, new Date(time)).price;
    const format = (value: Prisma.Decimal) => value.toFixed(instrument.pricePrecision);
    const candles: Candle[] = [];
    for (let index = limit - 1; index >= 0; index--) {
      const openMs = lastOpen - index * duration;
      const closeMs = openMs + duration;
      const open = mark(openMs), mid = mark(openMs + Math.floor(duration / 2)), close = mark(Math.min(closeMs - 1, cutoff - 1));
      const high = Prisma.Decimal.max(open, mid, close), low = Prisma.Decimal.min(open, mid, close);
      candles.push({ openTime: new Date(openMs).toISOString(), closeTime: new Date(closeMs).toISOString(),
        open: format(open), high: format(high), low: format(low), close: format(close), volume: null });
    }
    return { providerId: this.id, provider: this.name, sourceSymbol: instrument.symbol,
      effectiveInterval: timeframe, freshness: "SIMULATED", providerTimestamp: candles.at(-1)!.closeTime,
      isSyntheticOhlc: true, candles };
  }
}
