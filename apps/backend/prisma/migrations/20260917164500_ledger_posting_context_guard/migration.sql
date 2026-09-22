-- Prisma may execute a nested create/createMany inside a PostgreSQL
-- subtransaction. A subtransaction has a different current XID even though it
-- is part of the same atomic outer transaction, so the original XID-only guard
-- rejected valid application postings. Require a transaction-local marker for
-- the exact journal while retaining the XID check for compatible clients.
CREATE OR REPLACE FUNCTION primevest_prevent_late_ledger_entry()
RETURNS TRIGGER AS $$
DECLARE
  journal_xid TEXT;
  posting_journal_id TEXT;
BEGIN
  SELECT xmin::text
    INTO journal_xid
    FROM ledger_transactions
   WHERE id = NEW.transaction_id;

  posting_journal_id := current_setting(
    'primevest.posting_journal_id',
    true
  );

  IF journal_xid IS NULL OR (
    journal_xid <> pg_current_xact_id()::text
    AND posting_journal_id IS DISTINCT FROM NEW.transaction_id::text
  ) THEN
    RAISE EXCEPTION 'ledger_entries may only be added while their transaction is being posted'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public;
