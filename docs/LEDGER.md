# Ledger

PrimeVest uses immutable double-entry accounting. Amounts are positive decimal strings; each entry is explicitly debit or credit; total debit must equal total credit per currency before posting. Fast wallet fields are projections reconciled to ledger accounts and are never an admin-editable source of truth. Deposit, withdrawal, trade, fee, settlement, adjustment, reset, and reversal events use unique idempotency references. Corrections append inverse `REVERSAL` entries instead of mutating history.

Funding postings run at serializable isolation and take PostgreSQL row locks on the affected request and wallet. The database links each deposit credit and withdrawal lock/settlement to a unique ledger transaction. The service validates equal positive debit and credit totals before inserting entries; wallet projections change only inside the same transaction as their journal and request-state update.
