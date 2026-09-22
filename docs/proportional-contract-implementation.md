# Approved proportional contracts

Approved: BUY follows price change, SELL reverses it. Minimum stake BDT 10; maximum is available balance. Return has a zero floor and no profit cap. Hold to expiry for 30–31,536,000 seconds (365 days). Fees apply only to positive profit and are snapshotted at acceptance. Missing expiry observations remain pending; never substitute a later price.

## Implemented

- `PROPORTIONAL_V2` settlement with decimal arithmetic and BDT rounding to nearest paisa (half up).
- Legacy contracts retain `FIXED_PAYOUT_V1` behavior.
- Atomic stake locking, idempotency and exactly-once settlement journals.
- Initial crypto source `BINANCE_1S_V1:<symbol>USDT`: last fully closed UTC second before each boundary. Entry/expiry price and source timestamps are stored. This is a reference price contract; no assets are purchased on Binance.
- Contract source unavailable: admission rejected; existing settlement remains pending.
- Counterparty P&L and fee revenue ledger accounts for REAL, separate from customer clearing.
- Admin authentication and audited fee configuration at `/trading-settings`; no default administrator/password.
- Mobile amount/duration editing, no early-close selection, fee review, source-correct crypto labels and recovered server entry markers.
- Immutable PostgreSQL archive of requested entry/expiry observations, with per-process sharing of identical in-flight requests and a bounded concurrency ceiling. Financial transactions do not wait on external HTTP while holding wallet locks.
- Persisted, user-scoped mobile command recovery: interrupted submissions reuse the original body and idempotency key only after explicit retry confirmation. A pending uncertain request blocks a new trade.
- Net-of-fee chart estimates; expired unresolved trades show awaiting settlement, not a later live-price valuation. History shows returned funds and fees. Long-lived pending contracts are paginated independently of recent history.

## Verification

- Backend: all 85 tests passed, including PostgreSQL integration and compiled administrator HTTP tests; no skips. Tests use the separate `primevest_contract_verify` database, not customer balances.
- Mobile: all 29 tests passed; static analysis clean.
- Administrator HTTP test covers sign-in, fee bounds, an audited update, permission removal, and session revocation. Customer tokens cannot authorize administrator endpoints.
- Settlement tests cover BUY/SELL proportional returns, ties, no profit cap, zero payout floor, snapshotted fees, concurrent duplicate creation/settlement, insufficient funds, long-duration pagination, missing expiry observations and worker recovery.
- Mobile recovery test verifies the identical idempotency key and body survive a repository restart after a response timeout.
- Local deployed demo BUY and SELL completed 30-second lifecycles using Binance entry/expiry observations. SELL duplicate replay returned the same contract ID; stake 1000, entry 77416, expiry 77422.71 returned BDT 999.91 with zero locked funds afterward. REAL wallet remained zero.

Re-run backend verification after `pnpm --filter @primevest/backend prisma:generate` and `pnpm --filter @primevest/backend build`, with `DATABASE_URL` pointing at a migrated, seeded isolated test database and `RUN_DATABASE_INTEGRATION=true`: `pnpm --filter @primevest/backend exec vitest run --no-file-parallelism`. Serial file execution prevents fee-configuration fixtures interfering with settlement fixtures.

The USB device uses `PRIMEVEST_API_BASE_URL=http://127.0.0.1:3000/api/v1` and `adb reverse tcp:3000 tcp:3000`. Admin runs at `http://localhost:3001/trading-settings`. No port 8080 is used.

## Funding/admin follow-up — September 12

The funding/admin software gaps listed in the earlier checkpoint have now been implemented. See [funding and administrator operations](funding-admin-operations.md) for scope, verification and operator setup. This is not a record of production approval or proof of actual treasury capital.

- Private PNG/JPEG evidence submission, ClamAV scanning, metadata stripping, AES-GCM encryption, authenticated review and single-use evidence claims.
- Customer deposit submission and funding history, durable retry keys, and withdrawal status/balance events.
- Independent deposit verification/credit, withdrawal review/approval/payout receipt, hardware-key step-up and role checks.
- Admin workspace backed by live records; change proposals and independent approval for receiving numbers, fees, user controls, KYC, markets and roles.
- Reviewed treasury statements, customer coverage and reserve reporting, wallet/ledger reconciliation and version-specific release sign-offs with revocation/expiry checks.
- Verification: 95 backend/database tests plus 3 real ClamAV/MinIO tests; 31 mobile tests. Backend/admin lint/type checks and Flutter analysis passed. No actual treasury money or release signature was fabricated.

## Still required for full launch

- Bootstrap authorized administrator locally with `PRIMEVEST_ADMIN_EMAIL`, `PRIMEVEST_ADMIN_PASSWORD` (16+ characters) and `DATABASE_URL`, then run `pnpm --filter @primevest/backend exec tsx prisma/bootstrap-admin.ts`. Bootstrap never resets an existing password.
  Windows users can instead run `& .\infrastructure\scripts\setup-admin.ps1 -Email '<approved email>'` from the workspace. It prompts for a masked password and passes credentials by stdin to the backend container. The administrator is created only after that succeeds. The script does not store passwords in files or command arguments.
- Full infrastructure outage/restore drills and sustained-load evidence. The observation archive stores requested observations, not a continuous market tick archive. Due-batch scanning rotates through IDs so unavailable observations cannot starve later contracts.
- Actual operational funding, reviewed source statements and risk acceptance for uncapped future returns. No financial backing is manufactured by ledger entries.
- Approve additional instrument price sources, real instrument/user eligibility, and existing legal/provider/operational release requirements. Current runtime remains DEMO_ONLY.

Do not describe this as full production activation. Real funding/trading admission now also requires valid release sign-offs, covered treasury and clean wallet/ledger reconciliation. Payment-method seed preserves admin-edited receiving numbers.
