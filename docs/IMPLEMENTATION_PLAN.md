# PrimeVest Implementation Plan

## 2026-09 integrated production track

This plan is the implementation gate for moving the current demo UI to an
integrated application. Source changes must follow the dependency order below.

### Shared decisions

- The NestJS modular monolith owns identity, authorization, accounts, ledger,
  orders, executions, positions, funding state, audit and provider access.
- PostgreSQL is the only durable source of financial truth. Redis may cache,
  coordinate jobs and fan out events, but losing Redis must not change money.
- Flutter is an untrusted projection. It sends commands and renders server
  state; it never calculates an authoritative balance, fill, settlement or
  withdrawal result.
- `AccountMode` is `DEMO` or `REAL` on every account-scoped resource and
  command. Database constraints, ownership checks and service-layer checks
  prevent cross-mode joins or mutations.
- Money, price and quantity cross APIs as decimal strings and use PostgreSQL
  `NUMERIC` plus `Prisma.Decimal` on the server. Mobile decimal values are kept
  as strings/minor units and are never persisted as binary floating-point
  financial truth.
- REST responses use the existing `ApiEnvelope`; errors use stable `code`, a
  safe `message`, `requestId` and optional `details`. Financial commands require
  `Idempotency-Key`, which is bound to the actor, operation and request hash.
- Market display series and execution price evidence are different types.
  Display candles cannot be supplied as a client-selected fill price.
- Real execution, deposits and withdrawals remain fail-closed until approved
  provider adapters, credentials, operating permissions and reconciliation
  procedures are configured. Local integrated testing uses persisted demo
  transactions through the same service boundaries.

### Module ownership

| Module          | Owns                                                      | May depend on                                           |
| --------------- | --------------------------------------------------------- | ------------------------------------------------------- |
| Auth/Users      | credentials, sessions, profile, devices                   | Database, audit                                         |
| Accounts/Ledger | accounts, wallets, journals, balance projections          | Auth, database                                          |
| Markets         | instruments, normalized quotes/candles, provider adapters | Redis/cache, providers                                  |
| Trading         | orders, executions, positions, P/L, settlement            | Accounts/Ledger, Markets, Compliance, execution adapter |
| Funding         | deposit/withdrawal workflows                              | Accounts/Ledger, Compliance, KYC, payment adapter       |
| Notifications   | durable notices and delivery adapters                     | Domain events                                           |
| Admin/Audit     | RBAC, review commands, immutable activity evidence        | Auth and application services                           |

Modules call public application services, not another module's tables. Any
operation that changes financial state performs validation, idempotency,
locking, journal posting and domain-record updates in one database transaction.
External provider calls occur outside long-held database transactions and are
reconciled with durable provider identifiers.

### Dependency-ordered delivery

1. **Contract freeze** — align OpenAPI/shared types, envelopes, errors, enums,
   decimal/time rules, pagination, idempotency and environment names. Add
   contract fixtures so Dart and TypeScript parsers are tested against the same
   payload shapes.
2. **Identity integration** — retain Argon2id and rotating refresh sessions;
   add profile/current-user APIs. Replace mock mobile authentication with Dio,
   secure token storage, serialized refresh, logout and router guards.
3. **Accounts and ledger** — implement authenticated summaries, wallets,
   transactions and demo reset/provisioning. All queries require owner and mode.
4. **Authoritative demo trading** — implement idempotent market orders,
   executions, positions, close/settle, exact P/L and transaction history using
   PostgreSQL transactions and row locks. Real commands continue to fail closed.
5. **Market history and streaming** — support normalized `1m`, `5m`, `15m`,
   `30m`, `1h`, `4h`, `1d`, `1w`, `1M`; cursor history, bounded caching,
   WebSocket sequence/heartbeat/reconnect and snapshot recovery.
6. **Professional chart** — render OHLC candlesticks, green/red bodies,
   selected-candle OHLC, crosshair, pinch/zoom/pan and lazy history while
   retaining explicit provider/freshness labels.
7. **Mode integration** — introduce a prominent DEMO/REAL selector backed by
   server capabilities. Mode changes invalidate all account-scoped projections
   and cannot reuse balances, positions or histories from the other mode.
8. **Funding integration** — expose authenticated, idempotent request flows and
   history. Keep provider completion and admin approval unavailable until KYC,
   RBAC/maker-checker and payment adapters are approved and tested.
9. **Reliability and security** — structured redacted logs, metrics, rate and
   body limits, secret validation, TLS/network isolation, migrations, database
   backup/restore drills, retry policies and reconciliation jobs.
10. **Verification and release** — unit, database integration, contract, API,
    Flutter repository/widget, WebSocket failure and emulator E2E tests; restart
    containers/app and prove state persistence; perform a final dependency and
    security audit before producing a release artifact.

### Current implementation status (9 September 2026)

- Registration, login, logout, authenticated profile, Argon2id credentials,
  rotating hashed refresh sessions and replay-family revocation are integrated
  between Flutter, NestJS and PostgreSQL.
- DEMO and REAL accounts, wallets, balances, transactions, orders, executions,
  positions and audit/outbox records are persisted with account-mode and owner
  isolation. Demo order creation and close/settlement are idempotent and use
  transactional ledger postings. REAL commands remain fail-closed.
- Flutter uses secure token storage, serialized refresh, server-backed account
  selection, persisted demo trading and history. The separately labelled guest
  demo remains offline-only and cannot mutate authenticated account state.
- Charts render normalized OHLC candlesticks for all published intervals with
  candle inspection, crosshair, pinch zoom, pan and cursor-based history.
  Authenticated crypto screens receive sequenced Binance public kline updates
  over `/market` WebSocket with reconnect and REST snapshot recovery.
- PostgreSQL, Redis, MinIO, backend and admin run successfully under Docker. A
  release APK is installed on the Pixel 8 emulator and communicates with the
  local integrated stack through `10.0.2.2:3000`.
- Remaining release gates are explicit: approved broker/execution, KYC/AML and
  payment-provider integrations; production signing, secrets/TLS,
  monitoring and the applicable legal/provider licences. No unavailable gate is
  represented as working.

## Delivery rules

Every milestone ends with formatting, linting, type checking, automated tests, a production build, documentation updates, and a commit-ready tree. Claims of functionality require recorded commands. Real-money gates remain off until legal approval and provider details are explicitly supplied.

## Milestones

### 0 — Architecture and repository

- Architecture, database, API, security, and compliance contracts.
- Monorepo conventions and environment policy.
- Acceptance: documents agree on server authority, account separation, ledger invariants, and fail-closed gates.

### 1 — Runnable foundation

- pnpm workspace, NestJS API, Next.js admin shell, Flutter source, shared types/tokens.
- PostgreSQL, Redis, MinIO, Nginx and Docker Compose.
- Prisma baseline, Swagger, health/readiness, structured request identifiers.
- Acceptance: backend/admin build and tests pass; containers reach healthy state; Flutter validates on a Flutter-equipped host.

### 2 — Identity and demo account

- Registration/login, Argon2id, rotating refresh sessions, logout-all, recovery, verification abstractions, TOTP.
- Demo account creation and initial balanced funding transaction.
- Acceptance: security/session tests plus a user can enter demo mode with a reconciled ৳100,000.00.

### 3 — Markets

- Seed instruments across five asset classes, deterministic mock feed, quotes/candles, Redis cache, authorized WebSocket subscriptions, favorites/search.
- Flutter market list, asset details, chart and localization.
- Acceptance: simulator and stale/sequence tests; mobile shows explicitly simulated data.

### 4 — Normal demo trading

- Idempotent market/limit/stop orders, mock fills, positions, realized/unrealized P/L, close and history.
- Acceptance: buy uses ask, sell uses bid, concurrency/idempotency and ledger tests pass.

### 5 — Timed demo contracts

- Server-time contract creation, configurable durations/payouts, BullMQ schedule, evidence-backed settlement and countdown events.
- Acceptance: UP/DOWN/DRAW/VOID and settle-once tests; reconnect does not affect settlement.

### 6 — Ledger hardening

- Complete posting/reversal API, projections, reconciliation job and reports.
- Acceptance: property/concurrency tests prove balanced postings and no negative available balance.

### 7–9 — KYC, manual funding, admin

- Private upload/scanning adapter and manual review.
- bKash/Nagad request workflows, locks, maker-checker, proof and immutable accounting.
- Admin RBAC, queues, audit, fees, subscriptions, risk flags and CSV reporting.
- Acceptance: IDOR/RBAC, duplicate provider ID, double approval/payment and maker-checker tests.

### 10–11 — Hardening and external market data

- Rate/size limits, telemetry, alerts, backup/restore drill, load tests and deployment automation.
- Add a separately configured real market data adapter and reconciliation monitoring.

### 12 — Approved real execution only

Requires written compliance decision, permitted products/territories, authorized payment arrangements, broker/execution API contract, custody/funds-flow design, disclosures, reconciliation runbooks and operational incident ownership. No gate is enabled merely because an adapter compiles.

## Immediate next slice

Complete production observability, signing, failure drills and load tests. Real execution
and funding integration begins only after the required legal decisions and
approved broker, KYC and payment-provider contracts are supplied.
