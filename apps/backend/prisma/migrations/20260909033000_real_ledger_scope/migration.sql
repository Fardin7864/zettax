-- The real-money clearing control is explicitly REAL-scoped so the shared
-- LedgerService can reject journals that mix DEMO and REAL ledger accounts.
UPDATE ledger_accounts
   SET mode = 'REAL'
 WHERE code = 'PV:CASH_CLEARING:BDT';
