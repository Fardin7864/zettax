import type { SeedInstrument } from "../instruments";
import {
  MarketDataProviderError,
  type InstrumentQuote,
  type MarketDataProvider,
  type MarketInterval,
  type MarketStatus,
  type ProviderCandleSeries,
} from "../market-data.provider";

export abstract class HttpMarketDataProvider implements MarketDataProvider {
  abstract readonly id: string;
  abstract readonly name: string;
  abstract supports(instrument: SeedInstrument): boolean;

  connect(): Promise<void> {
    return Promise.resolve();
  }

  disconnect(): Promise<void> {
    return Promise.resolve();
  }

  subscribeQuotes(symbols: string[]): Promise<void> {
    void symbols;
    return Promise.reject(
      new MarketDataProviderError(this.id, "CAPABILITY_UNAVAILABLE"),
    );
  }

  unsubscribeQuotes(symbols: string[]): Promise<void> {
    void symbols;
    return Promise.reject(
      new MarketDataProviderError(this.id, "CAPABILITY_UNAVAILABLE"),
    );
  }

  getQuote(symbol: string): Promise<InstrumentQuote> {
    void symbol;
    return Promise.reject(
      new MarketDataProviderError(this.id, "CAPABILITY_UNAVAILABLE"),
    );
  }

  abstract getCandles(
    instrument: SeedInstrument,
    timeframe: MarketInterval,
    limit: number,
  ): Promise<ProviderCandleSeries>;

  getHistoricalCandles(
    instrument: SeedInstrument,
    timeframe: MarketInterval,
    limit: number,
  ): Promise<ProviderCandleSeries> {
    return this.getCandles(instrument, timeframe, limit);
  }

  getMarketStatus(symbol: string): Promise<MarketStatus> {
    void symbol;
    return Promise.resolve("UNKNOWN");
  }

  protected async fetchJson<T>(
    url: string,
    headers: Record<string, string> = {},
  ): Promise<T> {
    try {
      const response = await fetch(url, {
        headers: {
          Accept: "application/json",
          "User-Agent": "Zettax/0.1 market-display",
          ...headers,
        },
        signal: AbortSignal.timeout(8_000),
      });
      if (response.status === 429) {
        throw new MarketDataProviderError(this.id, "RATE_LIMITED");
      }
      if (!response.ok) {
        throw new MarketDataProviderError(this.id, "UNAVAILABLE");
      }
      return (await response.json()) as T;
    } catch (error) {
      if (error instanceof MarketDataProviderError) throw error;
      throw new MarketDataProviderError(this.id, "UNAVAILABLE");
    }
  }

  protected invalidResponse(): never {
    throw new MarketDataProviderError(this.id, "INVALID_RESPONSE");
  }
}
