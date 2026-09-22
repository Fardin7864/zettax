-- Ledger entries may only be inserted in the same database transaction that
-- created their journal. This closes the remaining append-only gap where a
-- later transaction could add a new balanced pair to an already posted journal.
CREATE FUNCTION primevest_prevent_late_ledger_entry()
RETURNS TRIGGER AS $$
DECLARE
  journal_xid TEXT;
BEGIN
  SELECT xmin::text
    INTO journal_xid
    FROM ledger_transactions
   WHERE id = NEW.transaction_id;

  IF journal_xid IS NULL OR journal_xid <> pg_current_xact_id()::text THEN
    RAISE EXCEPTION 'ledger_entries may only be added while their transaction is being posted'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ledger_entries_posting_window
BEFORE INSERT ON ledger_entries
FOR EACH ROW EXECUTE FUNCTION primevest_prevent_late_ledger_entry();
