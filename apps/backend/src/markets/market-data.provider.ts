import type { SeedInstrument } from "./instruments";

export type AssetClass = "CRYPTO" | "FOREX" | "STOCK" | "INDEX" | "COMMODITY";
export type MarketStatus = "OPEN" | "CLOSED" | "UNKNOWN";
export const MARKET_INTERVALS = [
  "1m",
  "5m",
  "15m",
  "30m",
  "1h",
  "4h",
  "1d",
  "1w",
  "1M",
] as const;
export type MarketInterval = (typeof MARKET_INTERVALS)[number];
export type MarketDataFreshness =
  "DISPLAY_LIVE" | "DELAYED" | "REFERENCE_DAILY" | "SIMULATED" | "SAMPLED";

export type Candle = {
  openTime: string;
  closeTime: string;
  open: string;
  high: string;
  low: string;
  close: string;
  volume: string | null;
};

export type InstrumentQuote = {
  instrumentId: string;
  symbol: string;
  bid: string;
  ask: string;
  last: string;
  mid: string;
  timestamp: string;
  providerTimestamp: string;
  receivedTimestamp: string;
  sequence: string;
  provider: string;
};

export type ProviderCandleSeries = {
  providerId: string;
  provider: string;
  sourceSymbol: string;
  effectiveInterval: MarketInterval;
  freshness: MarketDataFreshness;
  providerTimestamp: string;
  isSyntheticOhlc: boolean;
  candles: Candle[];
};

export type ProviderFailureReason =
  | "CAPABILITY_UNAVAILABLE"
  | "CONFIGURATION_REQUIRED"
  | "LICENSE_APPROVAL_REQUIRED"
  | "RATE_LIMITED"
  | "INVALID_RESPONSE"
  | "UNAVAILABLE";

export class MarketDataProviderError extends Error {
  constructor(
    readonly providerId: string,
    readonly reason: ProviderFailureReason,
  ) {
    super(`${providerId}:${reason}`);
  }
}

/** Vendor boundary. Unsupported capabilities must fail closed. */
export interface MarketDataProvider {
  readonly id: string;
  readonly name: string;
  supports(instrument: SeedInstrument): boolean;
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  subscribeQuotes(symbols: string[]): Promise<void>;
  unsubscribeQuotes(symbols: string[]): Promise<void>;
  getQuote(symbol: string): Promise<InstrumentQuote>;
  getCandles(
    instrument: SeedInstrument,
    timeframe: MarketInterval,
    limit: number,
    before?: Date,
  ): Promise<ProviderCandleSeries>;
  getHistoricalCandles(
    instrument: SeedInstrument,
    timeframe: MarketInterval,
    limit: number,
    before?: Date,
  ): Promise<ProviderCandleSeries>;
  getMarketStatus(symbol: string): Promise<MarketStatus>;
}
