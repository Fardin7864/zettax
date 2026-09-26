export type AssetClass = "CRYPTO" | "FOREX" | "STOCK" | "INDEX" | "COMMODITY";
export type MarketInterval =
  "1m" | "5m" | "15m" | "30m" | "1h" | "4h" | "1d" | "1w" | "1M";

export type Instrument = {
  id: string;
  symbol: string;
  name: string;
  assetClass: AssetClass;
  baseAsset: string;
  quoteAsset: string;
  pricePrecision: number;
  quantityPrecision: number;
};

export type Candle = {
  openTime: string;
  closeTime: string;
  open: string;
  high: string;
  low: string;
  close: string;
  volume: string | null;
};

export type CandleSeries = {
  instrumentId: string;
  symbol: string;
  requestedInterval: MarketInterval;
  effectiveInterval: MarketInterval;
  provider: string;
  providerTimestamp: string;
  freshness: string;
  isSyntheticOhlc: boolean;
  executionPrice: false;
  executionEligible: false;
  candles: Candle[];
};

type Envelope<T> = { data?: T };

async function getData<T>(url: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch(url, {
    ...(signal ? { signal } : {}),
    cache: "no-store",
  });
  const body = (await response.json()) as Envelope<T> & { message?: string };
  if (!response.ok || !body.data) {
    throw new Error(body.message || "Market data is temporarily unavailable.");
  }
  return body.data;
}

export function fetchInstruments(signal?: AbortSignal) {
  return getData<Instrument[]>("/api/market/instruments", signal);
}

export function fetchCandles(
  instrumentId: string,
  interval: MarketInterval,
  limit = 90,
  signal?: AbortSignal,
) {
  const query = new URLSearchParams({
    instrumentId,
    interval,
    limit: String(limit),
  });
  return getData<CandleSeries>(`/api/market/candles?${query}`, signal).then(
    (series) => {
      if (
        series.instrumentId !== instrumentId ||
        series.requestedInterval !== interval ||
        series.executionPrice !== false ||
        series.executionEligible !== false ||
        !Array.isArray(series.candles)
      ) {
        throw new Error("The market feed returned an invalid response.");
      }
      return series;
    },
  );
}

export function lastPrice(series?: CandleSeries) {
  return series && series.freshness !== "SIMULATED"
    ? Number(series.candles.at(-1)?.close)
    : NaN;
}

export function changePercent(series?: CandleSeries) {
  if (!series || series.freshness === "SIMULATED" || series.candles.length < 2)
    return NaN;
  const first = Number(
    series.effectiveInterval === "1h"
      ? series.candles[0]!.open
      : series.candles.at(-2)!.close,
  );
  const last = lastPrice(series);
  return first > 0 ? ((last - first) / first) * 100 : NaN;
}

export function formatPrice(value: number, precision = 2) {
  if (!Number.isFinite(value)) return "—";
  return new Intl.NumberFormat("en-US", {
    minimumFractionDigits: Math.min(precision, 2),
    maximumFractionDigits: precision,
  }).format(value);
}

export function formatChange(value: number) {
  return Number.isFinite(value)
    ? `${value >= 0 ? "+" : ""}${value.toFixed(2)}%`
    : "—";
}
