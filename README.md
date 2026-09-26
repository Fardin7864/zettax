# Zettax

Zettax is a Bangladesh-focused, dark-first trading platform being built demo-first. This repository contains a runnable NestJS API, a Next.js public website, a separate Next.js operations console, a Flutter mobile application, PostgreSQL/Prisma data layer, Redis, MinIO, Nginx, and Docker Compose.

**Current local mode:** authenticated DEMO trading and the REAL-labelled account
use server-authoritative virtual balances. Manual virtual bKash, Nagad and Rocket
requests can be reviewed by an administrator; they never transfer external
money. Public market data remains display-only, and no production broker or
payment API is represented as integrated. Production deployments remain
fail-closed unless their separate production configuration and controls are
completed.

## Quick start without Docker (recommended)

Requirements: Node 22+, pnpm 9, and a Supabase PostgreSQL project. Flutter stable is additionally required for mobile development.

```powershell
Copy-Item infrastructure/env/local-supabase.env.example .env.local
# Edit .env.local and provide the Supabase pooler DATABASE_URL.
pnpm install
pnpm dev:supabase
```

Open:

- API health: `http://localhost:3000/health`
- Swagger: `http://localhost:3000/api/docs`
- Admin shell: `http://localhost:3001`
- Public website: `http://localhost:3002`
- Supabase project: use its dashboard for database operations

The populated `.env.local` is ignored by source control. This workflow runs the NestJS API and Next.js admin directly and does not require Docker, local PostgreSQL, Redis, or MinIO. Redis and object-storage readiness checks are disabled only by this local launcher. Virtual funding does not require evidence uploads; production funding continues to fail closed until compatible object storage, ClamAV, and a 32-byte encryption-key file are configured.

To apply committed migrations deliberately, run `pnpm dev:supabase -- -ApplyMigrations`. Do not use destructive Prisma development migrations against a shared Supabase project.

Docker Compose remains available for isolated integration testing and for the existing single-VPS deployment; it is no longer mandatory for local app or admin development.

Backend startup applies committed Prisma migrations and runs an idempotent baseline seed before accepting traffic. The seed creates BDT, fail-closed feature-flag records, and an explicit non-real `MOCK` execution-provider record; it does not create users, deposits, withdrawals, or real balances. `/health` is process liveness, while `/ready` verifies PostgreSQL, Redis, and MinIO connectivity.

## Local Node development

```powershell
pnpm dev:supabase
```

Quality gate:

```powershell
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm --filter @primevest/backend prisma:validate
pnpm build
```

## Flutter mobile

The Android project wrapper is included. Flutter stable is installed separately from the repository and can build the client as follows:

```powershell
Set-Location apps/mobile
flutter pub get
flutter gen-l10n
dart format lib test
flutter analyze
flutter test
flutter build apk --release
```

The Android package ID is `com.primevest.app`. The current release configuration uses a development signature for direct demo installation; store delivery requires a protected production signing key and Play release configuration.

## Architecture and delivery references

- [System architecture](docs/SYSTEM_ARCHITECTURE.md)
- [Database design](docs/DATABASE_DESIGN.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [API contract](docs/API_CONTRACT.md)
- [Market-data operations](docs/MARKET_DATA_OPERATIONS.md)
- [Security model](docs/SECURITY_MODEL.md)
- [Compliance gates](docs/COMPLIANCE_GATES.md)
- [Deployment and backup operations](DEPLOYMENT.md)
- [Single-VPS production operations](docs/SINGLE_VPS_OPERATIONS.md)

## Backup and restore verification

`infrastructure/scripts/backup-postgres.ps1` writes compressed PostgreSQL custom-format backups with SHA-256 and metadata sidecars and enforces configurable retention. `restore-postgres.ps1` verifies the checksum, refuses to overwrite the source or an existing target, restores into a separate verification database, runs migration/ledger checks, and retains the database for inspection. These local files are not encrypted; production operations must move them to encrypted off-host storage and record full restore drills. See [deployment](DEPLOYMENT.md).

## Current scope

The mobile project now supports the integrated server flow: registration/login with secure token storage and refresh rotation, server-backed DEMO/REAL account selection, persisted virtual orders, positions and server-timed contracts, transaction history, and normalized external display-market data. Candlestick charts support the published intervals, candle inspection, zoom/pan, cursor-based historical loading, and authenticated sequenced Binance kline WebSocket updates with REST snapshot recovery. The private account stream persists its per-user sequence, refreshes balances and activity after durable events, and recovers changes missed while offline. A clearly isolated guest demo remains available for offline evaluation. In local `SANDBOX` mode the REAL-labelled account is explicitly shown as virtual and supports admin-reviewed virtual funding. Actual real-money trading and funding stay unavailable until the regulated production gates below are satisfied.

An earlier demo APK with legacy branding is [PrimeVest-Demo-v0.1.0.apk](deliverables/PrimeVest-Demo-v0.1.0.apk). The current Zettax debug APK is generated at `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`.

The backend includes an `ExecutionProvider` contract and deterministic `MockExecutionProvider`. The mock adapter rejects non-demo orders and cannot be selected as evidence of production execution. No real broker API has been fabricated or enabled.

## External display-market data

Chart data is isolated from order execution. Crypto candles use Binance's public Spot market-data endpoint without credentials. Forex falls back to keyless daily ECB reference-rate history through Frankfurter; this is reference data, not an intraday executable quote. Stocks, commodities, indices, and higher-frequency forex candles can use Twelve Data only when `TWELVE_DATA_API_KEY` is configured and the operator explicitly sets `TWELVE_DATA_DISPLAY_LICENSE_APPROVED=true` for that environment after confirming the intended display is permitted. A free or individual Twelve Data plan is suitable only for development/evaluation in this project; it does not authorize commercial external display or redistribution to client users. Production display requires an appropriate business agreement, attribution, and any exchange-specific licences.

Every candle response names its source and reports requested/effective interval, provider timestamp, receipt time, freshness class, synthetic-OHLC status, `executionPrice: false`, and `executionEligible: false`. `DISPLAY_LIVE` describes the upstream dataset class only; it is not a latency SLA, consolidated market view, or executable quote. An upstream failure returns a stable API error. The separate offline mobile demo may then use clearly labelled simulated charts, but external data is never silently relabelled or used to settle real-money activity. Provider limitations, licensing checks, caching, failure behavior, and the release test plan are documented in [market-data operations](docs/MARKET_DATA_OPERATIONS.md).

For local Android-emulator development the app defaults to `http://10.0.2.2:3000/api/v1`. Release builds should provide the deployed HTTPS API URL:

```powershell
flutter build apk --release --dart-define=PRIMEVEST_API_BASE_URL=https://api.zettax.app/api/v1
```

## Production approval boundary

`PRODUCTION_APPROVED` is an operational state, not a development shortcut. It requires documented legal/compliance approval references, an approved provider agreement and credentials, a separately implemented and reviewed provider adapter, KYC/AML and risk controls, signed customer disclosures, reconciliation procedures, production secrets, TLS, monitoring, backup/restore proof, and an authorized bKash/Nagad merchant workflow. Until those external prerequisites and control reviews are complete, keep `COMPLIANCE_MODE=DEMO_ONLY`, `EXECUTION_PROVIDER=MOCK`, and every real-money flag disabled.

## Verification record

On 9 September 2026, the backend passed Prettier, ESLint, TypeScript checks,
production compilation and 51 tests across 11 files with PostgreSQL integration
enabled. The database-backed tests cover ledger immutability, concurrent
idempotent demo reset/order/settlement, user and account isolation, outbox
skip-locked claiming/retry, funding state rules, market normalization, realtime
event safety, Argon2id sessions and refresh-token replay handling. Flutter passed
analysis and all 23 repository, market-data, chart and widget tests.

The current Docker stack reports PostgreSQL, Redis, MinIO, backend and admin as
healthy; `/health` returns `ok` and `/ready` reports every dependency `up`. An
authenticated live Socket.IO subscription received normalized Binance kline
updates marked `executionPrice: false` and `executionEligible: false`. The
release APK was rebuilt, installed on `emulator-5554`, and verified on the Trade
screen with the provider-labelled WebSocket feed and persisted demo balance.

The live authentication smoke test registered a synthetic user, created isolated demo and real BDT accounts, posted the ৳100,000 non-withdrawable demo opening balance as a balanced ledger transaction, created a database-backed session, rotated its refresh token, logged out, and confirmed the revoked access token returns 401. Live funding checks confirmed deposits and withdrawals return their explicit disabled codes in demo mode, unauthenticated admin access returns 401, and none of those safety failures restart the backend. The database contains the applied initial migration, BDT seed, Argon2id password hash, zero unbalanced ledger transactions, and fail-closed compliance and feature flags.

The mobile app passes Flutter analysis and tests, builds as an Android release APK, installs on a Pixel 8 emulator, launches successfully, and completes a demo BUY-to-portfolio flow without fatal application logs. APK metadata and signature were independently verified with Android build tools.
The NestJS backend now includes real database-backed user registration, login, Argon2id password hashing, short-lived access tokens, rotating hashed refresh tokens, replay-family revocation, device sessions, logout, and failed-login lockout. See [docs/API_CONTRACT.md](docs/API_CONTRACT.md) and [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md).
