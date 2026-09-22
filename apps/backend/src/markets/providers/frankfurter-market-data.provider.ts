import { Injectable } from "@nestjs/common";
import type { SeedInstrument } from "../instruments";
import type {
  Candle,
  MarketInterval,
  ProviderCandleSeries,
} from "../market-data.provider";
import { HttpMarketDataProvider } from "./http-market-data.provider";

type FrankfurterRate = {
  date?: string;
  base?: string;
  quote?: string;
  rate?: number;
  providers?: Array<string | { key?: string }>;
};

@Injectable()
export class FrankfurterMarketDataProvider extends HttpMarketDataProvider {
  readonly id = "FRANKFURTER_ECB";
  readonly name = "Frankfurter / ECB reference rates";

  supports(instrument: SeedInstrument): boolean {
    return instrument.assetClass === "FOREX";
  }

  async getCandles(
    instrument: SeedInstrument,
    _timeframe: MarketInterval,
    limit: number,
    before?: Date,
  ): Promise<ProviderCandleSeries> {
    const upperBound = before?.getTime() ?? Date.now();
    const from = new Date(upperBound - (limit * 2 + 10) * 86_400_000)
      .toISOString()
      .slice(0, 10);
    const query = new URLSearchParams({
      from,
      to: new Date(upperBound - 1).toISOString().slice(0, 10),
      base: instrument.baseAsset,
      quotes: instrument.quoteAsset,
      providers: "ECB",
      expand: "providers",
    });
    const payload = await this.fetchJson<unknown>(
      `https://api.frankfurter.dev/v2/rates?${query.toString()}`,
    );
    if (!Array.isArray(payload)) this.invalidResponse();
    const rows = (payload as FrankfurterRate[]).slice(-limit);
    const candles: Candle[] = rows.map((row, index) => {
      if (
        !row.date ||
        !/^\d{4}-\d{2}-\d{2}$/.test(row.date) ||
        typeof row.rate !== "number" ||
        !Number.isFinite(row.rate) ||
        row.rate <= 0 ||
        row.base !== instrument.baseAsset ||
        row.quote !== instrument.quoteAsset ||
        !row.providers?.some((provider) =>
          typeof provider === "string"
            ? provider === "ECB"
            : provider.key === "ECB",
        )
      ) {
        this.invalidResponse();
      }
      const previous = rows[index - 1]?.rate ?? row.rate;
      if (typeof previous !== "number") this.invalidResponse();
      return {
        openTime: `${row.date}T00:00:00.000Z`,
        closeTime: `${row.date}T23:59:59.999Z`,
        open: String(previous),
        high: String(Math.max(previous, row.rate)),
        low: String(Math.min(previous, row.rate)),
        close: String(row.rate),
        volume: null,
      };
    });
    if (candles.length === 0) this.invalidResponse();
    return {
      providerId: this.id,
      provider: this.name,
      sourceSymbol: `${instrument.baseAsset}/${instrument.quoteAsset}`,
      effectiveInterval: "1d",
      freshness: "REFERENCE_DAILY",
      providerTimestamp: candles.at(-1)!.closeTime,
      isSyntheticOhlc: true,
      candles,
    };
  }
}
