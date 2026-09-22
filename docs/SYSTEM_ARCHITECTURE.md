# PrimeVest System Architecture

## Architectural intent

PrimeVest starts as a modular monolith: one NestJS deployment owns business invariants, one PostgreSQL database is the system of record, Redis supports ephemeral cache, subscriptions, locks, and BullMQ jobs, and MinIO stores private development files. The Flutter app and Next.js admin consume versioned APIs; neither is trusted to enforce financial or compliance policy.

The first production-shaped milestone is demo-only. `COMPLIANCE_MODE=DEMO_ONLY` is fail-closed, real balances never participate in demo activity, and production execution adapters do not exist until an approved provider and legal operating model are supplied.

## Runtime view

```text
Flutter mobile ─┐                         ┌─ PostgreSQL (authoritative state)
                ├─ HTTPS/WSS ─ NestJS ───┼─ Redis (cache, locks, BullMQ)
Next.js admin ──┘              │          └─ MinIO (private objects)
                              │
                              ├─ MarketDataProvider
                              │    ├─ external display adapters (server-side)
                              │    └─ simulated fallback (offline demo only)
                              └─ ExecutionProvider
                                   └─ MockExecutionProvider (demo only)
```

Nginx terminates TLS, applies request limits and security headers, and proxies API, WebSocket, and admin traffic. Mobile clients subscribe only to PrimeVest's gateway; they never fan out directly to external price vendors.

## Backend modules and boundaries

- **Identity:** registration, Argon2id credentials, rotating hashed refresh tokens, devices, step-up authentication, and security events.
- **Compliance:** the authoritative mode and per-capability feature gates. Every regulated command checks these gates in the service layer.
- **Accounts:** strictly separates `DEMO` and `REAL` accounts.
- **Markets:** normalized instruments, quotes, candles, provider health, stale-data detection, and subscriptions.
- **Trading:** idempotent orders, executions, positions, and paper execution. Real execution is a separately injected adapter.
- **Timed contracts:** server timestamps, immutable price evidence, BullMQ expiry scheduling, and idempotent settlement.
- **Ledger:** balanced, immutable transactions and entries. Balances are projections, never editable primary truth.
- **Funding:** manual deposit/withdrawal workflows that post ledger transactions only after controlled approval.
- **KYC/storage:** private uploads, metadata validation, signed URLs, scan state, and maker-checker review.
- **Admin/RBAC/audit:** granular permission checks and append-only audit evidence for every sensitive mutation.
- **Risk/notifications/reporting:** review flags, delivery adapters, and permissioned operational exports.

Modules call one another through application services, not through another module's tables. Financial commands use a PostgreSQL transaction and row/advisory locks as appropriate. External I/O happens outside a database transaction unless the result can be made idempotent and reconciled.

## Trust boundaries

1. The phone and browser are untrusted. Server time, current price, account ownership, fees, permissions, and flags are recomputed by the backend.
2. Admin users are authenticated but not universally trusted. Permission and object checks apply per action, with maker-checker for configured operations.
3. Provider data is validated for schema, monotonic sequence, and freshness before use.
4. Object storage is private. The API issues short-lived, purpose-bound URLs after authorization.
5. Redis is not accounting truth. Loss of Redis may reduce availability but cannot change balances or settlement history.

## Core invariants

- Real operations require `PRODUCTION_APPROVED`, the relevant feature flag, an enabled instrument/account, and an approved provider.
- Demo and real ledger accounts, wallets, orders, positions, and contracts cannot cross.
- Money uses `NUMERIC`/`Decimal` and serialized decimal strings.
- Every ledger transaction has entries whose debits equal credits in the same currency.
- Every financial command has an idempotency boundary and an audit trail.
- A timed contract records entry evidence once and settlement evidence once; a database uniqueness constraint prevents a second settlement.
- Corrections append reversals; financial and audit history is never deleted.
- Display-market data is provenance-labelled and cannot cross the execution boundary merely because an upstream feed is available.

## Environments

Local, development, staging, and production use the same containers with environment-specific secrets and adapters. Local can use public display-data adapters or the clearly labelled offline simulator, and always uses demo-only mock execution. Production refuses startup when secrets are weak, HTTPS assumptions are violated, or regulated gates are enabled without an explicit approved mode/provider configuration. Production market display additionally requires documented provider and exchange display/redistribution rights; a free development key is not sufficient.

## Scaling path

The modular monolith scales horizontally behind Nginx. WebSocket subscriptions use Redis fan-out; BullMQ workers may run separately; market ticks are cached/broadcast without a write per connected user. Only modules with demonstrated independent scaling or reliability needs should later be extracted.
