-- Customer wallets and contracts are denominated in USD. Funding requests
-- retain their BDT payment amounts and snapshot the admin-set conversion rate.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM primevest.wallets w
    JOIN primevest.accounts a ON a.id = w.account_id
    WHERE a.mode = 'REAL' AND w.currency_code = 'BDT'
      AND (w.available_projection <> 0 OR w.locked_projection <> 0)
  ) OR EXISTS (SELECT 1 FROM primevest.positions WHERE status = 'OPEN')
    OR EXISTS (SELECT 1 FROM primevest.timed_contracts WHERE result = 'PENDING')
    OR EXISTS (SELECT 1 FROM primevest.deposit_requests)
    OR EXISTS (SELECT 1 FROM primevest.withdrawal_requests)
  THEN
    RAISE EXCEPTION 'USD cutover requires reconciliation of existing live balances or requests';
  END IF;
END $$;

INSERT INTO primevest.currencies (code, name, precision)
VALUES ('USD', 'US Dollar', 2)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE primevest.deposit_requests
  ADD COLUMN usd_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
  ADD COLUMN conversion_rate_bdt_per_usd DECIMAL(12,4) NOT NULL DEFAULT 125;

ALTER TABLE primevest.withdrawal_requests
  ADD COLUMN usd_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
  ADD COLUMN conversion_rate_bdt_per_usd DECIMAL(12,4) NOT NULL DEFAULT 118;

-- Historic requests, if any exist in a development copy, receive a visible
-- calculated amount. Production was reset before this migration.
UPDATE primevest.deposit_requests
SET usd_amount = ROUND(amount / conversion_rate_bdt_per_usd, 2);
UPDATE primevest.withdrawal_requests
SET usd_amount = ROUND(amount / conversion_rate_bdt_per_usd, 2);

-- Existing accounts use a fresh USD wallet. Their prior BDT demo journals
-- remain unchanged for audit; real BDT wallets must be empty at cutover.
DO $$
DECLARE
  account_row RECORD;
  control_id UUID;
  available_id UUID;
  locked_id UUID;
  journal_id UUID;
BEGIN
  INSERT INTO primevest.ledger_accounts
    (id, currency_code, code, name, type, mode)
  VALUES (gen_random_uuid(), 'USD', 'PV:DEMO:FUNDING:USD',
    'Demo funding control', 'ASSET', 'DEMO')
  ON CONFLICT (code) DO NOTHING;
  SELECT id INTO control_id FROM primevest.ledger_accounts
    WHERE code = 'PV:DEMO:FUNDING:USD';

  FOR account_row IN SELECT id, mode FROM primevest.accounts LOOP
    INSERT INTO primevest.wallets
      (id, account_id, currency_code, available_projection, locked_projection, updated_at)
    VALUES (gen_random_uuid(), account_row.id, 'USD',
      CASE WHEN account_row.mode = 'DEMO' THEN 1000 ELSE 0 END, 0, now())
    ON CONFLICT (account_id, currency_code) DO NOTHING;

    INSERT INTO primevest.ledger_accounts
      (id, account_id, currency_code, code, name, type, mode)
    VALUES (gen_random_uuid(), account_row.id, 'USD',
      'PV:USER:' || account_row.id || ':AVAILABLE:USD',
      'Customer funds available', 'LIABILITY', account_row.mode)
    ON CONFLICT (code) DO NOTHING;
    SELECT id INTO available_id FROM primevest.ledger_accounts
      WHERE code = 'PV:USER:' || account_row.id || ':AVAILABLE:USD';

    INSERT INTO primevest.ledger_accounts
      (id, account_id, currency_code, code, name, type, mode)
    VALUES (gen_random_uuid(), account_row.id, 'USD',
      'PV:USER:' || account_row.id || ':LOCKED:USD',
      'Customer funds locked', 'LIABILITY', account_row.mode)
    ON CONFLICT (code) DO NOTHING;
    SELECT id INTO locked_id FROM primevest.ledger_accounts
      WHERE code = 'PV:USER:' || account_row.id || ':LOCKED:USD';

    IF account_row.mode = 'DEMO' THEN
      INSERT INTO primevest.ledger_transactions
        (id, type, idempotency_key, description, posted_at)
      VALUES (gen_random_uuid(), 'DEMO_FUNDING',
        'usd-demo-cutover:' || account_row.id,
        'Initialize USD demo wallet after currency cutover', now())
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING id INTO journal_id;
      IF journal_id IS NOT NULL THEN
        PERFORM set_config('primevest.posting_journal_id', journal_id::text, true);
        INSERT INTO primevest.ledger_entries
          (id, transaction_id, ledger_account_id, direction, amount, created_at)
        VALUES
          (gen_random_uuid(), journal_id, control_id, 'DEBIT', 1000, now()),
          (gen_random_uuid(), journal_id, available_id, 'CREDIT', 1000, now());
      END IF;
    END IF;
    journal_id := NULL;
  END LOOP;
END $$;
