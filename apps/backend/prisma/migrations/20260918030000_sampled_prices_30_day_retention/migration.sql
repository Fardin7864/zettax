CREATE TABLE sampled_prices (
  id BIGSERIAL PRIMARY KEY,
  instrument_slug VARCHAR(80) NOT NULL REFERENCES instruments(slug) ON DELETE CASCADE,
  price DECIMAL(24, 8) NOT NULL CHECK (price > 0),
  sampled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  provider VARCHAR(80) NOT NULL,
  CONSTRAINT sampled_prices_instrument_slug_sampled_at_key UNIQUE (instrument_slug, sampled_at)
);
CREATE INDEX sampled_prices_sampled_at_idx ON sampled_prices(sampled_at);
