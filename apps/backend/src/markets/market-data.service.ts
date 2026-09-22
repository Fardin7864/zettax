import { HttpStatus, Injectable, Optional } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ApiErrorException } from "../http/api-error";
import { instruments } from "./instruments";
import {
  MARKET_INTERVALS,
  MarketDataProviderError,
  type Candle,
  type MarketDataFreshness,
  type MarketDataProvider,
  type MarketInterval,
} from "./market-data.provider";
import { BinanceMarketDataProvider } from "./providers/binance-market-data.provider";
import { FrankfurterMarketDataProvider } from "./providers/frankfurter-market-data.provider";
import { TwelveDataMarketDataProvider } from "./providers/twelve-data-market-data.provider";
import { SandboxMarketDataProvider } from "./providers/sandbox-market-data.provider";
import { DemoPriceService } from "../trading/demo-price.service";
import { SampledPriceService } from "./sampled-price.service";

type InstrumentAssetClass = (typeof instruments)[number]["assetClass"];

export type CandleSeries = {
  instrumentId: string;
  symbol: string;
  assetClass: InstrumentAssetClass;
  requestedInterval: MarketInterval;
  effectiveInterval: MarketInterval;
  providerId: string;
  provider: string;
  sourceSymbol: string;
  freshness: MarketDataFreshness;
  providerTimestamp: string;
  receivedAt: string;
  executionPrice: false;
  executionEligible: false;
  isSyntheticOhlc: boolean;
  nextCursor: string | null;
  candles: Candle[];
};

type CacheEntry = { expiresAt: number; value: CandleSeries };

@Injectable()
export class MarketDataService {
  private readonly cache = new Map<string, CacheEntry>();
  private readonly pending = new Map<string, Promise<CandleSeries>>();

  constructor(
    private readonly config: ConfigService,
    private readonly binance: BinanceMarketDataProvider,
    private readonly frankfurter: FrankfurterMarketDataProvider,
    private readonly twelveData: TwelveDataMarketDataProvider,
    private readonly sandbox: SandboxMarketDataProvider = new SandboxMarketDataProvider(
      new DemoPriceService(),
    ),
    @Optional() private readonly sampledPrices?: SampledPriceService,
  ) {}

  async candles(
    instrumentId: string,
    interval: MarketInterval = "1h",
    limit = 90,
    before?: string,
  ): Promise<CandleSeries> {
    const instrument = instruments.find((item) => item.id === instrumentId);
    if (!instrument) {
      throw new ApiErrorException(
        "INSTRUMENT_NOT_FOUND",
        "The requested instrument does not exist.",
        HttpStatus.NOT_FOUND,
      );
    }
    if (!MARKET_INTERVALS.includes(interval)) {
      throw new ApiErrorException(
        "UNSUPPORTED_INTERVAL",
        `Supported intervals are ${MARKET_INTERVALS.join(", ")}.`,
        HttpStatus.BAD_REQUEST,
      );
    }
    if (!Number.isInteger(limit) || limit < 10 || limit > 200) {
      throw new ApiErrorException(
        "INVALID_CANDLE_LIMIT",
        "Candle limit must be an integer from 10 to 200.",
        HttpStatus.BAD_REQUEST,
      );
    }
    const beforeDate = before ? new Date(before) : undefined;
    if (
      beforeDate &&
      (!Number.isFinite(beforeDate.getTime()) ||
        beforeDate.getTime() > Date.now())
    ) {
      throw new ApiErrorException(
        "INVALID_CANDLE_CURSOR",
        "The historical candle cursor must be a valid past UTC timestamp.",
        HttpStatus.BAD_REQUEST,
      );
    }

    const sampled =
      this.sampledPrices?.enabled && this.sampledPrices.supports(instrument.id);
    if (sampled) {
      const result = await this.sampledPrices.candles(
        instrument,
        interval,
        limit,
        beforeDate,
      );
      return {
        instrumentId: instrument.id,
        symbol: instrument.symbol,
        assetClass: instrument.assetClass,
        requestedInterval: interval,
        ...result,
        receivedAt: new Date().toISOString(),
        executionPrice: false,
        executionEligible: false,
        nextCursor:
          result.candles.length === limit
            ? (result.candles[0]?.openTime ?? null)
            : null,
      };
    }
    const provider = this.providerFor(instrument.assetClass);
    const cacheKey = `${provider.id}:${instrument.id}:${interval}:${limit}:${beforeDate?.toISOString() ?? "latest"}`;
    const cached = this.cache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) return cached.value;
    if (cached) this.cache.delete(cacheKey);

    const existing = this.pending.get(cacheKey);
    if (existing) return existing;

    const request = provider
      .getCandles(instrument, interval, limit, beforeDate)
      .then((result) => {
        const value: CandleSeries = {
          instrumentId: instrument.id,
          symbol: instrument.symbol,
          assetClass: instrument.assetClass,
          requestedInterval: interval,
          ...result,
          receivedAt: new Date().toISOString(),
          executionPrice: false,
          executionEligible: false,
          nextCursor:
            result.candles.length === limit
              ? (result.candles[0]?.openTime ?? null)
              : null,
        };
        this.setCache(cacheKey, value);
        return value;
      })
      .catch((error: unknown) => this.handleProviderError(error))
      .finally(() => this.pending.delete(cacheKey));
    this.pending.set(cacheKey, request);
    return request;
  }

  private providerFor(assetClass: InstrumentAssetClass): MarketDataProvider {
    if (assetClass === "CRYPTO") return this.binance;
    if (assetClass === "FOREX" && !this.twelveDataEnabled) {
      return this.frankfurter;
    }
    if (
      !this.twelveDataEnabled &&
      this.config.get<string>("COMPLIANCE_MODE") === "SANDBOX"
    )
      return this.sandbox;
    return this.twelveData;
  }

  private setCache(key: string, value: CandleSeries): void {
    while (this.cache.size >= this.maxCacheEntries) {
      const oldestKey = this.cache.keys().next().value;
      if (!oldestKey) break;
      this.cache.delete(oldestKey);
    }
    const ttlMs =
      value.freshness === "DISPLAY_LIVE"
        ? 10_000
        : value.freshness === "DELAYED"
          ? 60_000
          : 3_600_000;
    this.cache.set(key, { expiresAt: Date.now() + ttlMs, value });
  }

  private handleProviderError(error: unknown): never {
    if (error instanceof MarketDataProviderError) {
      if (error.reason === "CONFIGURATION_REQUIRED") {
        throw new ApiErrorException(
          "MARKET_DATA_KEY_REQUIRED",
          "This asset class requires a configured market-data provider.",
          HttpStatus.SERVICE_UNAVAILABLE,
        );
      }
      if (error.reason === "LICENSE_APPROVAL_REQUIRED") {
        throw new ApiErrorException(
          "MARKET_DATA_LICENSE_REQUIRED",
          "Display rights have not been approved for this market-data provider.",
          HttpStatus.SERVICE_UNAVAILABLE,
        );
      }
      if (error.reason === "RATE_LIMITED") {
        throw new ApiErrorException(
          "MARKET_DATA_RATE_LIMITED",
          "Market data is temporarily rate limited. Please try again later.",
          HttpStatus.SERVICE_UNAVAILABLE,
        );
      }
    }
    throw new ApiErrorException(
      "MARKET_DATA_UNAVAILABLE",
      "Display market data is temporarily unavailable.",
      HttpStatus.SERVICE_UNAVAILABLE,
    );
  }

  private get twelveDataEnabled(): boolean {
    return Boolean(
      this.config.get<string>("TWELVE_DATA_API_KEY")?.trim() &&
      this.config.get<string>("TWELVE_DATA_DISPLAY_LICENSE_APPROVED") ===
        "true",
    );
  }

  private get maxCacheEntries(): number {
    const configured = Number(
      this.config.get<string>("MARKET_DATA_CACHE_MAX_ENTRIES") ?? "500",
    );
    return Number.isInteger(configured) &&
      configured >= 10 &&
      configured <= 5000
      ? configured
      : 500;
  }
}
