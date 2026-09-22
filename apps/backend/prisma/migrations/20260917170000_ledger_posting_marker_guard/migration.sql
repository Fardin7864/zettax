-- Authorize ledger entry creation with a transaction-local marker for the
-- exact journal being posted. The marker is set by LedgerService immediately
-- before inserting entries and cannot authorize a different journal.
--
-- Do not query an unqualified ledger_transactions table here: this database
-- hosts PrimeVest in a dedicated schema, and a fixed function search_path can
-- otherwise inspect the same-named table in the wrong schema.
CREATE OR REPLACE FUNCTION primevest_prevent_late_ledger_entry()
RETURNS TRIGGER AS $$
DECLARE
  posting_journal_id TEXT;
BEGIN
  posting_journal_id := current_setting(
    'primevest.posting_journal_id',
    true
  );

  IF posting_journal_id IS DISTINCT FROM NEW.transaction_id::text THEN
    RAISE EXCEPTION 'ledger_entries may only be added while their transaction is being posted'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog;
