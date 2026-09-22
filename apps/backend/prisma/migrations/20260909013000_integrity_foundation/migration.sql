-- Stable public instrument identity.
ALTER TABLE "instruments" ADD COLUMN "slug" VARCHAR(80);
UPDATE "instruments"
SET "slug" = CASE "symbol"
  WHEN 'BTC/USD' THEN 'btc-usd'
  WHEN 'ETH/USD' THEN 'eth-usd'
  WHEN 'SOL/USD' THEN 'sol-usd'
  WHEN 'XRP/USD' THEN 'xrp-usd'
  WHEN 'EUR/USD' THEN 'eur-usd'
  WHEN 'GBP/USD' THEN 'gbp-usd'
  WHEN 'USD/JPY' THEN 'usd-jpy'
  WHEN 'AUD/USD' THEN 'aud-usd'
  WHEN 'AAPL' THEN 'aapl'
  WHEN 'MSFT' THEN 'msft'
  WHEN 'NVDA' THEN 'nvda'
  WHEN 'S&P 500' THEN 'spx'
  WHEN 'NASDAQ 100' THEN 'ndx'
  WHEN 'XAU/USD' THEN 'xau-usd'
  WHEN 'XAG/USD' THEN 'xag-usd'
  ELSE lower(regexp_replace("symbol", '[^a-zA-Z0-9]+', '-', 'g'))
END;
ALTER TABLE "instruments" ALTER COLUMN "slug" SET NOT NULL;
CREATE UNIQUE INDEX "instruments_slug_key" ON "instruments"("slug");

-- Composite account ownership prevents a denormalized user/account mismatch.
CREATE UNIQUE INDEX "accounts_id_user_id_key" ON "accounts"("id", "user_id");
ALTER TABLE "orders" DROP CONSTRAINT "orders_account_id_fkey";
ALTER TABLE "timed_contracts" DROP CONSTRAINT "timed_contracts_account_id_fkey";
ALTER TABLE "deposit_requests" DROP CONSTRAINT "deposit_requests_account_id_fkey";
ALTER TABLE "withdrawal_requests" DROP CONSTRAINT "withdrawal_requests_account_id_fkey";
ALTER TABLE "orders" ADD CONSTRAINT "orders_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "orders" ADD CONSTRAINT "orders_account_id_user_id_fkey"
  FOREIGN KEY ("account_id", "user_id") REFERENCES "accounts"("id", "user_id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "timed_contracts" ADD CONSTRAINT "timed_contracts_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "timed_contracts" ADD CONSTRAINT "timed_contracts_account_id_user_id_fkey"
  FOREIGN KEY ("account_id", "user_id") REFERENCES "accounts"("id", "user_id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "deposit_requests" ADD CONSTRAINT "deposit_requests_account_id_user_id_fkey"
  FOREIGN KEY ("account_id", "user_id") REFERENCES "accounts"("id", "user_id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "withdrawal_requests" ADD CONSTRAINT "withdrawal_requests_account_id_user_id_fkey"
  FOREIGN KEY ("account_id", "user_id") REFERENCES "accounts"("id", "user_id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "fee_rules" ADD CONSTRAINT "fee_rules_instrument_id_fkey"
  FOREIGN KEY ("instrument_id") REFERENCES "instruments"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Durable command deduplication and transactional event publication.
CREATE TYPE "IdempotencyStatus" AS ENUM ('PROCESSING', 'COMPLETED', 'FAILED');
CREATE TABLE "idempotency_commands" (
  "id" UUID NOT NULL,
  "actor_type" "ActorType" NOT NULL,
  "actor_id" VARCHAR(128) NOT NULL,
  "operation" VARCHAR(128) NOT NULL,
  "key" VARCHAR(128) NOT NULL,
  "request_hash" CHAR(64) NOT NULL,
  "status" "IdempotencyStatus" NOT NULL DEFAULT 'PROCESSING',
  "response" JSONB,
  "error_code" VARCHAR(128),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  "expires_at" TIMESTAMP(3),
  CONSTRAINT "idempotency_commands_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "idempotency_commands_actor_id_nonempty" CHECK (length(trim("actor_id")) > 0),
  CONSTRAINT "idempotency_commands_request_hash_format" CHECK ("request_hash" ~ '^[0-9a-f]{64}$')
);
CREATE UNIQUE INDEX "idempotency_commands_actor_type_actor_id_operation_key_key"
  ON "idempotency_commands"("actor_type", "actor_id", "operation", "key");
CREATE INDEX "idempotency_commands_status_created_at_idx"
  ON "idempotency_commands"("status", "created_at");
CREATE INDEX "idempotency_commands_expires_at_idx" ON "idempotency_commands"("expires_at");

CREATE TABLE "outbox_events" (
  "id" UUID NOT NULL,
  "aggregate_type" VARCHAR(128) NOT NULL,
  "aggregate_id" VARCHAR(128) NOT NULL,
  "event_type" VARCHAR(160) NOT NULL,
  "payload" JSONB NOT NULL,
  "occurred_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "published_at" TIMESTAMP(3),
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "last_error" TEXT,
  CONSTRAINT "outbox_events_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "outbox_events_attempts_nonnegative" CHECK ("attempts" >= 0),
  CONSTRAINT "outbox_events_names_nonempty" CHECK (
    length(trim("aggregate_type")) > 0 AND length(trim("aggregate_id")) > 0 AND length(trim("event_type")) > 0
  )
);
CREATE INDEX "outbox_events_published_at_occurred_at_idx"
  ON "outbox_events"("published_at", "occurred_at");
CREATE INDEX "outbox_events_aggregate_type_aggregate_id_occurred_at_idx"
  ON "outbox_events"("aggregate_type", "aggregate_id", "occurred_at");

-- Database-level financial and market shape constraints.
ALTER TABLE "wallets" ADD CONSTRAINT "wallets_available_nonnegative" CHECK ("available_projection" >= 0);
ALTER TABLE "wallets" ADD CONSTRAINT "wallets_locked_nonnegative" CHECK ("locked_projection" >= 0);
ALTER TABLE "ledger_entries" ADD CONSTRAINT "ledger_entries_amount_positive" CHECK ("amount" > 0);
ALTER TABLE "orders" ADD CONSTRAINT "orders_quantity_positive" CHECK ("quantity" > 0);
ALTER TABLE "orders" ADD CONSTRAINT "orders_filled_quantity_valid" CHECK ("filled_quantity" >= 0 AND "filled_quantity" <= "quantity");
ALTER TABLE "orders" ADD CONSTRAINT "orders_fees_nonnegative" CHECK ("fees" >= 0);
ALTER TABLE "executions" ADD CONSTRAINT "executions_values_valid" CHECK ("quantity" > 0 AND "price" > 0 AND "fee" >= 0);
ALTER TABLE "positions" ADD CONSTRAINT "positions_quantity_positive" CHECK ("quantity" > 0);
ALTER TABLE "timed_contracts" ADD CONSTRAINT "timed_contract_values_valid" CHECK ("investment_amount" > 0 AND "entry_price" > 0 AND "payout_rate" >= 0 AND "expiry_timestamp" > "entry_timestamp");
ALTER TABLE "timed_contract_settlements" ADD CONSTRAINT "timed_settlement_values_valid" CHECK ("expiry_price" > 0 AND "payout_amount" >= 0);
ALTER TABLE "payment_methods" ADD CONSTRAINT "payment_method_limits_valid" CHECK ("minimum_deposit" > 0 AND "maximum_deposit" >= "minimum_deposit" AND "fee_value" >= 0);
ALTER TABLE "deposit_requests" ADD CONSTRAINT "deposit_amount_positive" CHECK ("amount" > 0);
ALTER TABLE "withdrawal_requests" ADD CONSTRAINT "withdrawal_amount_positive" CHECK ("amount" > 0);
ALTER TABLE "candles" ADD CONSTRAINT "candle_ohlc_valid" CHECK (
  "open" > 0 AND "high" > 0 AND "low" > 0 AND "close" > 0 AND
  "high" >= "low" AND "open" BETWEEN "low" AND "high" AND "close" BETWEEN "low" AND "high" AND
  ("volume" IS NULL OR "volume" >= 0)
);
ALTER TABLE "market_quotes" ADD CONSTRAINT "market_quote_values_valid" CHECK (
  "bid" > 0 AND "ask" > 0 AND "last" > 0 AND "ask" >= "bid"
);

-- A journal must finish with at least two positive entries and equal debits/credits.
CREATE FUNCTION primevest_assert_balanced_ledger_transaction(target_id UUID)
RETURNS VOID AS $$
DECLARE
  entry_count BIGINT;
  difference NUMERIC;
BEGIN
  SELECT count(*), COALESCE(sum(CASE WHEN direction = 'DEBIT' THEN amount ELSE -amount END), 0)
    INTO entry_count, difference
    FROM ledger_entries
   WHERE transaction_id = target_id;
  IF entry_count < 2 OR difference <> 0 THEN
    RAISE EXCEPTION 'ledger transaction % is not balanced', target_id USING ERRCODE = '23514';
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION primevest_check_ledger_transaction_insert()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM primevest_assert_balanced_ledger_transaction(NEW.id);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER ledger_transaction_balanced_on_commit
AFTER INSERT ON ledger_transactions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION primevest_check_ledger_transaction_insert();

CREATE FUNCTION primevest_prevent_financial_mutation()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE = '55000';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ledger_transactions_append_only
BEFORE UPDATE OR DELETE ON ledger_transactions
FOR EACH ROW EXECUTE FUNCTION primevest_prevent_financial_mutation();
CREATE TRIGGER ledger_entries_append_only
BEFORE UPDATE OR DELETE ON ledger_entries
FOR EACH ROW EXECUTE FUNCTION primevest_prevent_financial_mutation();
CREATE TRIGGER audit_logs_append_only
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION primevest_prevent_financial_mutation();
