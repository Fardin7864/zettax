-- Add only provider-verified Binance spot pairs to the trading catalogue.
INSERT INTO "instruments" ("id", "slug", "symbol", "name", "asset_class", "base_asset", "quote_asset", "price_precision", "quantity_precision", "market_status", "demo_enabled", "real_enabled")
SELECT gen_random_uuid(), v.slug, v.symbol, v.name, 'CRYPTO'::"AssetClass", v.base_asset, 'USD', v.price_precision, v.quantity_precision, 'DISPLAY_DATA', true, false
FROM (VALUES
  ('ada-usd', 'ADA/USD', 'Cardano', 'ADA', 4, 4),
  ('doge-usd', 'DOGE/USD', 'Dogecoin', 'DOGE', 5, 4),
  ('avax-usd', 'AVAX/USD', 'Avalanche', 'AVAX', 3, 4),
  ('dot-usd', 'DOT/USD', 'Polkadot', 'DOT', 3, 4),
  ('link-usd', 'LINK/USD', 'Chainlink', 'LINK', 3, 4),
  ('ltc-usd', 'LTC/USD', 'Litecoin', 'LTC', 2, 6),
  ('bch-usd', 'BCH/USD', 'Bitcoin Cash', 'BCH', 2, 6),
  ('trx-usd', 'TRX/USD', 'TRON', 'TRX', 5, 4),
  ('uni-usd', 'UNI/USD', 'Uniswap', 'UNI', 3, 4),
  ('atom-usd', 'ATOM/USD', 'Cosmos', 'ATOM', 3, 4),
  ('near-usd', 'NEAR/USD', 'NEAR Protocol', 'NEAR', 4, 4),
  ('shib-usd', 'SHIB/USD', 'Shiba Inu', 'SHIB', 8, 2),
  ('apt-usd', 'APT/USD', 'Aptos', 'APT', 4, 4),
  ('sui-usd', 'SUI/USD', 'Sui', 'SUI', 4, 4),
  ('pepe-usd', 'PEPE/USD', 'Pepe', 'PEPE', 8, 2)
) AS v(slug, symbol, name, base_asset, price_precision, quantity_precision)
ON CONFLICT ("slug") DO NOTHING;

INSERT INTO "instrument_configs" ("instrument_id", "minimum_trade", "maximum_trade", "spread_bps", "max_quote_age_ms")
SELECT i.id, 1, 100000, 10, 5000 FROM "instruments" i
WHERE i.slug IN ('ada-usd', 'doge-usd', 'avax-usd', 'dot-usd', 'link-usd', 'ltc-usd', 'bch-usd', 'trx-usd', 'uni-usd', 'atom-usd', 'near-usd', 'shib-usd', 'apt-usd', 'sui-usd', 'pepe-usd')
ON CONFLICT ("instrument_id") DO NOTHING;
