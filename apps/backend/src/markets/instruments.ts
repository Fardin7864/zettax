import type { AssetClass } from "./market-data.provider";

export type SeedInstrument = {
  id: string;
  symbol: string;
  name: string;
  assetClass: AssetClass;
  baseAsset: string;
  quoteAsset: string;
  pricePrecision: number;
  quantityPrecision: number;
};

export const instruments: SeedInstrument[] = [
  ["btc-usd", "BTC/USD", "Bitcoin", "CRYPTO", "BTC", "USD", 2, 8],
  ["eth-usd", "ETH/USD", "Ethereum", "CRYPTO", "ETH", "USD", 2, 8],
  ["sol-usd", "SOL/USD", "Solana", "CRYPTO", "SOL", "USD", 3, 6],
  ["xrp-usd", "XRP/USD", "XRP", "CRYPTO", "XRP", "USD", 5, 4],
  ["eur-usd", "EUR/USD", "Euro / US Dollar", "FOREX", "EUR", "USD", 5, 2],
  [
    "gbp-usd",
    "GBP/USD",
    "British Pound / US Dollar",
    "FOREX",
    "GBP",
    "USD",
    5,
    2,
  ],
  [
    "usd-jpy",
    "USD/JPY",
    "US Dollar / Japanese Yen",
    "FOREX",
    "USD",
    "JPY",
    3,
    2,
  ],
  [
    "aud-usd",
    "AUD/USD",
    "Australian Dollar / US Dollar",
    "FOREX",
    "AUD",
    "USD",
    5,
    2,
  ],
  ["aapl", "AAPL", "Apple", "STOCK", "AAPL", "USD", 2, 4],
  ["msft", "MSFT", "Microsoft", "STOCK", "MSFT", "USD", 2, 4],
  ["nvda", "NVDA", "NVIDIA", "STOCK", "NVDA", "USD", 2, 4],
  ["spx", "S&P 500", "S&P 500 Index", "INDEX", "SPX", "USD", 2, 4],
  ["ndx", "NASDAQ 100", "NASDAQ 100 Index", "INDEX", "NDX", "USD", 2, 4],
  ["xau-usd", "XAU/USD", "Gold", "COMMODITY", "XAU", "USD", 2, 4],
  ["xag-usd", "XAG/USD", "Silver", "COMMODITY", "XAG", "USD", 3, 4],
].map(
  ([
    id,
    symbol,
    name,
    assetClass,
    baseAsset,
    quoteAsset,
    pricePrecision,
    quantityPrecision,
  ]) => ({
    id: id as string,
    symbol: symbol as string,
    name: name as string,
    assetClass: assetClass as AssetClass,
    baseAsset: baseAsset as string,
    quoteAsset: quoteAsset as string,
    pricePrecision: pricePrecision as number,
    quantityPrecision: quantityPrecision as number,
  }),
);
