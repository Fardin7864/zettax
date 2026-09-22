# PrimeVest Database Design

## Principles

PostgreSQL is the authoritative store. UUID primary keys avoid enumerable identifiers. All user-owned reads include ownership predicates. Financial quantities are `NUMERIC`, timestamps are UTC `timestamptz`, and operational tables carry created/updated timestamps where mutation is legitimate.

The executable Prisma schema is at `apps/backend/prisma/schema.prisma` and is the canonical implementation reference.

## Aggregate map

| Aggregate      | Key records                                       | Safety constraint                                              |
| -------------- | ------------------------------------------------- | -------------------------------------------------------------- |
| Identity       | users, profiles, sessions, devices, security      | refresh token hashes only; sessions revoke independently       |
| Accounts       | accounts, wallets, currencies                     | account mode is immutable; unique wallet per account/currency  |
| Markets        | instruments, configs, quotes, candles             | quote sequence/provider evidence retained                      |
| Trading        | orders, executions, positions                     | `(account_id, client_order_id)` is unique                      |
| Timed          | timed_contracts, settlements                      | one settlement per contract                                    |
| Ledger         | accounts, transactions, entries                   | postings immutable and transaction-balanced                    |
| Funding        | payment methods, deposits, withdrawals            | normalized provider transaction identifiers unique by provider |
| Compliance     | KYC cases/documents, risk flags, legal acceptance | private object keys, explicit review state                     |
| Administration | admins, roles, permissions, audit logs            | append-only evidence; least-privilege mappings                 |

## Ledger model

Balances are derived by summing posted entries. A wallet may maintain transactionally updated projections (`available`, `locked`) for fast reads, but reconciliation always compares projections with ledger totals.

Each `ledger_transactions` row represents one business event and has two or more `ledger_entries`. Entries contain debit or credit, never both. The posting service validates:

1. at least two entries;
2. all amounts are positive decimal values;
3. total debit equals total credit per currency;
4. referenced accounts accept that currency and account mode;
5. idempotency key is unique within the operation scope.

Posted transactions cannot be updated or deleted. A correction creates a `REVERSAL` referencing the original transaction and posts inverse entries.

Example demo funding:

```text
Debit  Demo Funds Clearing        ৳100,000.00
Credit User Demo Cash Liability   ৳100,000.00
```

## Concurrency

- Withdrawal creation locks the wallet projection row, verifies available funds, then atomically moves available to locked through ledger/projection postings.
- Deposit approval locks the deposit request and rejects any state other than `PENDING_REVIEW`.
- Order submission uses a unique account/client-order identifier and stores the HTTP idempotency key.
- Timed settlement locks the contract, checks its terminal state, and inserts through the unique contract settlement relationship.
- Provider transaction IDs are normalized (trimmed and uppercase) before a scoped unique constraint is evaluated.

## Retention and privacy

Authentication/session data follows a configured security retention policy. Financial, KYC-review, legal-acceptance, and audit records follow regulatory retention policy and are not subject to casual user deletion. Account deletion is implemented as controlled anonymization/closure where retention obligations require records to remain.

KYC files are never database blobs. The database stores private object keys, hashes, declared/detected MIME type, byte size, scan status, and review metadata.

## Index strategy

Indexes prioritize user timelines, state queues, symbol search, open positions, expiring contracts, and audit lookup. High-frequency quote retention will be bounded/partitioned before production volume; Redis carries the latest quote. Query plans and index hit rates must be measured in staging rather than adding speculative indexes.

## Migration discipline

Migrations are generated in development, reviewed in pull requests, applied with `prisma migrate deploy`, and never use destructive reset commands in production. Deployments back up, run migration checks, apply forward migrations, and verify readiness. Rollback uses a reviewed compensating migration or application rollback compatible with the migrated schema.
