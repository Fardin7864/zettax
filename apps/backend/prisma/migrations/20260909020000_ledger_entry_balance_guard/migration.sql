-- Recheck the complete journal whenever entries are appended. Together with
-- the transaction-insert constraint trigger, this prevents unbalanced direct
-- SQL/ORM writes both during initial posting and after a journal exists.
CREATE FUNCTION primevest_check_ledger_entry_insert()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM primevest_assert_balanced_ledger_transaction(NEW.transaction_id);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER ledger_entry_balanced_on_commit
AFTER INSERT ON ledger_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION primevest_check_ledger_entry_insert();
