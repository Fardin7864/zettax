-- Pin function resolution to the private application schema. This prevents
-- callers from shadowing referenced objects through a mutable search_path.
ALTER FUNCTION primevest_assert_balanced_ledger_transaction(UUID)
  SET search_path = primevest, pg_temp;
ALTER FUNCTION primevest_check_ledger_transaction_insert()
  SET search_path = primevest, pg_temp;
ALTER FUNCTION primevest_prevent_financial_mutation()
  SET search_path = primevest, pg_temp;
ALTER FUNCTION primevest_check_ledger_entry_insert()
  SET search_path = primevest, pg_temp;
ALTER FUNCTION primevest_prevent_late_ledger_entry()
  SET search_path = primevest, pg_temp;
ALTER FUNCTION protect_evidence_claim()
  SET search_path = primevest, pg_temp;
ALTER FUNCTION protect_operation_evidence()
  SET search_path = primevest, pg_temp;
ALTER FUNCTION prevent_contract_price_rewrite()
  SET search_path = primevest, pg_temp;
