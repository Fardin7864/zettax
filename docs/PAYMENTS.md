# Payments

Initial bKash and Nagad support is a manual request-and-review workflow, not an automated payment integration. Receiving account information is admin-configured and must comply with provider merchant rules. A deposit becomes value only through an idempotent, balanced ledger posting after approval. Withdrawals lock available value at request, release it on rejection, and settle only after required provider reference/proof is recorded. Both features remain backend-disabled outside an approved production mode.

## Implemented server workflow

- Deposit submissions normalize the provider transaction ID, enforce a unique payment-method/reference pair and a per-user idempotency key, and start in `PENDING_REVIEW`.
- Deposit approval locks the request row and atomically posts `DEBIT Manual MFS cash clearing / CREDIT Customer available liability`, updates the wallet projection, and marks the request `CREDITED`. Repeating the same approval returns the existing result.
- Withdrawal creation requires an active real account, approved KYC, an enabled bKash/Nagad method, and sufficient available funds. A serializable transaction locks the wallet and posts `DEBIT Available liability / CREDIT Locked liability`.
- Admin review must follow `REQUESTED -> UNDER_REVIEW -> APPROVED -> PROCESSING -> PAID`. `PAID` requires a normalized, unique provider transaction ID and atomically posts `DEBIT Locked liability / CREDIT Manual MFS cash clearing`.
- Rejection before processing, or user cancellation before review, appends an immutable reversal of the lock transaction and returns the projection to available funds.
- Every financial state change writes an audit record in the same database transaction.

## Production prerequisites

The routes deliberately fail closed until `COMPLIANCE_MODE=PRODUCTION_APPROVED` and the relevant server flags are enabled. Before enabling them, PrimeVest still needs documented legal/compliance approval, approved merchant accounts and provider terms, configured official receiving numbers, admin authentication/RBAC and step-up authentication, maker-checker policy, private evidence storage and malware scanning, fee rules, transaction monitoring/limits, operational reconciliation, and tested incident/refund procedures. No automated bKash or Nagad API is represented by this module.
