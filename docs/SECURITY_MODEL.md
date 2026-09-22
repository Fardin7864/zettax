# PrimeVest Security Model

## Security posture

PrimeVest assumes clients, networks, and individual sessions can be hostile. Authorization and business invariants are enforced in NestJS services on every request. Controls align with OWASP API and mobile guidance, with additional accounting, idempotency, and maker-checker safeguards for financial commands.

## Identity and sessions

- Passwords use Argon2id with reviewed memory/time parameters and optional future pepper support.
- Access tokens are short-lived. Refresh tokens rotate on every use and only hashes are stored.
- Refresh-token reuse revokes the token family and raises a security/risk event.
- Sessions retain device and coarse IP/user-agent metadata; users can revoke one or all devices.
- TOTP secrets are encrypted at rest. Recovery codes are single-use hashes.
- Withdrawal, credential changes, 2FA removal, and sensitive profile changes require recent step-up authentication.
- Login, recovery, and OTP endpoints have per-IP and per-account throttles without revealing account existence.

Implemented authentication uses Argon2id with 64 MiB memory, three iterations, and one lane. Login failures use the same public error for unknown users, incorrect passwords, and temporary lockout; known accounts are temporarily locked after the configured threshold. Refresh JWTs carry a session ID, token-family ID, and monotonic version. Rotation uses an optimistic database update, while version/hash mismatch revokes the family and creates a risk flag. Access-token validation checks the backing session on every protected request, so logout and administrative login disablement take effect immediately.

## Authorization

User APIs scope all records to the authenticated subject; UUIDs alone never grant access. Admin APIs require explicit permissions such as `kyc.approve` or `withdrawal.mark_paid`. Support access does not imply finance authority. Configured dual control rejects self-approval.

## Compliance gates

The backend evaluates `COMPLIANCE_MODE` and per-feature gates at startup and for each command. Environment variables provide safe bootstrap defaults; database configuration enables audited runtime changes. The effective result is the more restrictive source. `DEMO_ONLY` always rejects real trading, deposits, and withdrawals regardless of client payload.

## Financial integrity

- Decimal arithmetic only; no JavaScript floating point for value calculations.
- Database transactions, locks, unique constraints, state-machine guards, and request idempotency protect mutations.
- Ledger transactions and audit records are append-only. Corrections are reversals.
- Deposit/withdrawal provider references are normalized and duplicate-protected.
- Quote staleness and provider health fail closed. Price evidence is independent of direction and retained for disputes.
- Reconciliation compares wallet projections, ledger totals, provider executions, and authorized external cash accounts.

## Data protection

- TLS is mandatory outside local development; HSTS and secure headers are applied at the edge.
- Secrets remain in environment/secret stores and are never committed or logged.
- KYC and payment evidence uses private buckets, MIME/signature/size validation, malware scan states, encryption, and short-lived signed URLs.
- Logs redact credentials, OTPs, tokens, identity images, document numbers, and payment secrets.
- Database backups are encrypted, access-controlled, retention-limited, and routinely restore-tested.

## Application and infrastructure controls

- Global DTO validation strips unknown fields; request bodies and uploads are bounded.
- Parameterized Prisma access prevents raw SQL injection by default; any raw query requires review.
- CORS uses an allowlist. Swagger is restricted/disabled as appropriate in production.
- Dependencies, containers, IaC, and mobile artifacts are scanned in CI.
- `/health` and `/ready` expose minimal detail publicly; detailed telemetry requires operational access.
- Structured logs carry request/correlation IDs without secrets; OpenTelemetry provides metrics/traces.

## Threat-focused tests

Required suites cover refresh replay, brute force, RBAC and IDOR, private file access, duplicate deposits, double approval/settlement, concurrent withdrawals, negative balances, idempotency fingerprint mismatch, stale/manipulated quote sequences, WebSocket cross-user access, and fail-closed compliance configuration.

## Incident response

Runbooks must support session-family revocation, provider disablement, trading/deposit/withdrawal kill switches, evidence preservation, reconciliation, affected-user identification, credential rotation and auditable recovery. Availability controls must never bypass ledger or compliance invariants.
