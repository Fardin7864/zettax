import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import type { SeedInstrument } from "../instruments";
import {
  MarketDataProviderError,
  type Candle,
  type MarketInterval,
  type ProviderCandleSeries,
} from "../market-data.provider";
import { HttpMarketDataProvider } from "./http-market-data.provider";

const intervals: Record<MarketInterval, string> = {
  "1m": "1min",
  "5m": "5min",
  "15m": "15min",
  "30m": "30min",
  "1h": "1h",
  "4h": "4h",
  "1d": "1day",
  "1w": "1week",
  "1M": "1month",
};

type TwelveDataPayload = {
  status?: string;
  values?: Array<{
    datetime?: string;
    open?: string;
    high?: string;
    low?: string;
    close?: string;
    volume?: string | null;
  }>;
};

@Injectable()
export class TwelveDataMarketDataProvider extends HttpMarketDataProvider {
  readonly id = "TWELVE_DATA";
  readonly name = "Twelve Data";
  private requestWindowStartedAt = 0;
  private requestsInWindow = 0;

  constructor(private readonly config: ConfigService) {
    super();
  }

  supports(instrument: SeedInstrument): boolean {
    return instrument.assetClass !== "CRYPTO";
  }

  async getCandles(
    instrument: SeedInstrument,
    timeframe: MarketInterval,
    limit: number,
    before?: Date,
  ): Promise<ProviderCandleSeries> {
    const apiKey = this.apiKey;
    if (!apiKey) {
      throw new MarketDataProviderError(this.id, "CONFIGURATION_REQUIRED");
    }
    if (!this.displayLicenseApproved) {
      throw new MarketDataProviderError(this.id, "LICENSE_APPROVAL_REQUIRED");
    }
    this.consumeRequestBudget();
    const sourceSymbol = this.symbol(instrument);
    const query = new URLSearchParams({
      symbol: sourceSymbol,
      interval: intervals[timeframe],
      outputsize: String(limit),
      timezone: "UTC",
    });
    if (before) {
      query.set(
        "end_date",
        before.toISOString().replace("T", " ").slice(0, 19),
      );
    }
    const payload = await this.fetchJson<TwelveDataPayload>(
      `https://api.twelvedata.com/time_series?${query.toString()}`,
      { Authorization: `apikey ${apiKey}` },
    );
    if (payload.status === "error" || !Array.isArray(payload.values)) {
      this.invalidResponse();
    }
    const durationMs = this.intervalDuration(timeframe);
    const candles: Candle[] = payload.values
      .map((row) => {
        const { datetime, open, high, low, close, volume } = row;
        if (
          !datetime ||
          !open ||
          !high ||
          !low ||
          !close ||
          ![open, high, low, close].every((value) => this.isDecimal(value))
        ) {
          this.invalidResponse();
        }
        const openTime = new Date(`${datetime.replace(" ", "T")}Z`);
        if (!Number.isFinite(openTime.getTime())) this.invalidResponse();
        return {
          openTime: openTime.toISOString(),
          closeTime: new Date(openTime.getTime() + durationMs).toISOString(),
          open,
          high,
          low,
          close,
          volume: volume && this.isDecimal(volume) ? volume : null,
        };
      })
      .reverse();
    if (candles.length === 0) this.invalidResponse();
    return {
      providerId: this.id,
      provider: this.name,
      sourceSymbol,
      effectiveInterval: timeframe,
      freshness: "DELAYED",
      providerTimestamp: candles.at(-1)!.closeTime,
      isSyntheticOhlc: false,
      candles,
    };
  }

  private consumeRequestBudget(): void {
    const now = Date.now();
    if (now - this.requestWindowStartedAt >= 60_000) {
      this.requestWindowStartedAt = now;
      this.requestsInWindow = 0;
    }
    if (this.requestsInWindow >= this.requestsPerMinute) {
      throw new MarketDataProviderError(this.id, "RATE_LIMITED");
    }
    this.requestsInWindow += 1;
  }

  private symbol(instrument: SeedInstrument): string {
    return instrument.assetClass === "FOREX" ||
      instrument.assetClass === "COMMODITY"
      ? `${instrument.baseAsset}/${instrument.quoteAsset}`
      : instrument.baseAsset;
  }

  private intervalDuration(interval: MarketInterval): number {
    return {
      "1m": 60_000,
      "5m": 300_000,
      "15m": 900_000,
      "30m": 1_800_000,
      "1h": 3_600_000,
      "4h": 14_400_000,
      "1d": 86_400_000,
      "1w": 604_800_000,
      "1M": 2_592_000_000,
    }[interval];
  }

  private isDecimal(value: string): boolean {
    return /^\d+(?:\.\d+)?$/.test(value);
  }

  private get apiKey(): string | undefined {
    return this.config.get<string>("TWELVE_DATA_API_KEY")?.trim() || undefined;
  }

  private get displayLicenseApproved(): boolean {
    return (
      this.config.get<string>("TWELVE_DATA_DISPLAY_LICENSE_APPROVED") === "true"
    );
  }

  private get requestsPerMinute(): number {
    const configured = Number(
      this.config.get<string>("TWELVE_DATA_REQUESTS_PER_MINUTE") ?? "8",
    );
    return Number.isInteger(configured) && configured >= 1 && configured <= 60
      ? configured
      : 8;
  }
}
