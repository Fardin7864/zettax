# Funding and administrator operations

Implemented September 12, 2026. Local runtime: backend 3000, admin 3001, USB application via adb reverse 3000. The existing Next.js/Docker deployment was retained; no new hosting provider was introduced. This document distinguishes implemented controls from evidence that operators must supply.

## Initial administrator setup

### Updated operator policy

FIDO2 is optional at the owner's request. Use **Confirm password** to authorize changes for five minutes, or use a registered security key. Password confirmation is single-factor reauthentication, **not MFA** and not equivalent to a hardware key's phishing resistance. Five failed confirmations in fifteen minutes lock further confirmation; endpoint throttling also applies. Independent funding/configuration approval remains enforced. The administrator password minimum remains 16 characters.

`funding@primevest.com` is intended for the separate funding operator, with the `funding-reviewer` role: deposit/withdrawal review, private funding evidence and a limited overview. It cannot change fees, payment numbers, user controls, roles, treasury statements or release approvals. An email/account does not establish an independent person: a separate authorized human must exclusively control it. Passwords shared in chat must be replaced locally before production.

Legal/compliance approval can reference documents held at the office using **Reference office-held documents**. Record the file ID, custodian, approval date, product/jurisdiction scope and expiry; an appropriately authorized signer must attest. Document upload is not mandatory for these two gates. This does not substitute office references for treasury statements, testing evidence, or the remaining release gates. No office document was examined or legal approval inferred from its existence.

These updates supersede the hardware-key requirement in the original checklist below. The VPS production tests and actual capital remain outstanding; runtime activation has not been authorized by evidence records. Follow-up verification: 97 backend/database tests passed, including password confirmation, lockout and office-held legal references; backend/admin lint and build checks passed. No browser work was performed for this follow-up.

1. Keep Docker Desktop and the PrimeVest backend running. Open PowerShell in `H:\projects\treding-app`.
2. Run `./infrastructure/scripts/setup-admin.ps1 -Email "intimiti18@gmail.com"`.
3. Enter and confirm a unique password of at least 16 characters at the masked local prompts. Never send it in chat. The script passes it through stdin, not a command argument or file; the backend stores an Argon2id hash. It never resets an existing account.
4. Open `http://localhost:3001` and sign in with that email/password. Click **Register security key**, insert a physical FIDO2 key, and complete its PIN/touch prompt. Registration requires user verification and a non-synced credential. This is not hardware-attestation certification; device provenance must be approved operationally.
5. **Verify security key** grants five minutes for changes. Login sessions last fifteen minutes, remain in browser memory and disappear on page reload. An expired session requires another sign-in. Register a backup key while an existing key is verified; recovery for lost keys requires a separate audited operator procedure, not a web bypass.
6. A different actual person needs a separate email/password/key for funding checks. Run the same local bootstrap command with their approved email; they must enter their own password locally. Do not create multiple identities for one person to bypass independence. Never share operator credentials.

The bootstrap role is `operations`. Release authority roles exist but are NOT automatically assigned. Propose a role change from **Admins**, using an ID from **Roles**, and have another authorized operator approve it in **Changes**. Neither requester nor checker can be the recipient of a role change, so privilege changes require a third administrator. Establish the necessary real staff before release approval work.

## Customer funding and review

- Cash In uses server-configured bKash, Nagad and Rocket receiving details and PERSONAL/AGENT types. Receiving numbers are hidden and submissions blocked while release/compliance gates are closed. Existing configured numbers are preserved by deployment.
- Customer supplies amount, sending mobile, transaction ID and a PNG/JPEG screenshot (5 MB maximum). Both original and normalized image are scanned; evidence is encrypted before MinIO upload and bound to its owner, purpose and object key. Unavailable scanning/storage rejects the upload.
- Deposits stay pending and do not affect balance. The first operator views evidence and verifies the actual provider statement/reference. A screenshot is not proof of received money by itself. A different operator approves the credit; one balanced ledger transaction is posted even on repeated/concurrent requests.
- Withdrawals lock available funds once. Operator A starts review, operator B approves, and a paying operator distinct from B records the actual completed payout transaction ID and clean receipt. The platform does not automatically send bKash/Nagad/Rocket transfers. Do not mark paid until external payment is independently confirmed. Processing payouts cannot be cancelled as if unpaid.
- Funding history is accessible from the history icon on Cash In/Withdraw. Admin status filters include credited/paid/rejected records. Account events refresh wallet projections after funding decisions.
- Interrupted mobile requests retain the original body and idempotency key in user-scoped secure storage. Explicit retry uses that original command. A subsequent outage/gate failure must not discard an earlier uncertain outcome.

## Admin scope

Live overview, deposit/withdrawal review, payment methods, treasury, release, trading terms, customers, KYC cases, contracts, markets, ledger, risk flags, audit, administrators, role directory and proposed changes are connected to backend records. Password hashes are never returned. Identity case approval requires submitted cases with clean documents; this console does not itself provide sanctions/PEP screening or certify a legal result.

Payment details, positive-profit fee, customer control flags, KYC decisions, market availability and role assignments go through **Changes**. Approval requires a different operator with the relevant permission, current requester authority and an unchanged record fingerprint. Stale requests can be rejected and recreated. Direct fee/payment PATCH routes are removed. Changes apply to future trades; existing contract terms remain snapshotted.

## Treasury and release

- Upload timestamped statement evidence and identify each real external account consistently. CUSTOMER funds and RESERVE capital cannot share the same account identity/category. A different operator verifies statements; reviewed records cannot be rewritten.
- Dashboard counts the latest approved statement per account, ignores evidence older than 24 hours or no longer clean, compares customer assets with REAL wallet available+locked liabilities, and reports reserve capital and pending stakes. Wallet projections are checked against posted ledger balances.
- These are point-in-time reviewed statements, not a live bank feed. They do not prevent an operator entering a false external balance; verification remains a human responsibility. A finite reserve does not guarantee uncapped BUY profits or uninterrupted settlement.
- Eleven release gates must be signed for the exact deployed `RELEASE_VERSION`, by their separately authorized roles and at least five distinct signers. Evidence is private and single-use. Signatures expire within 90 days and may be revoked; inactive signers, revoked roles or quarantined evidence invalidate readiness. `local-unapproved` cannot become ready.
- Signing gates does NOT flip runtime flags. Real admission also requires server-side production/compliance flags, instrument/user eligibility, treasury coverage and clean reconciliation. Existing obligations/settlements must not be rewritten or paid using a later substituted expiry observation.

## Secrets, deployment and recovery

Migration `20260912040000_funding_operations` is additive and was applied after a local database backup. Corrective migrations, not destructive rollback, are the recovery path.

Local evidence key: `infrastructure/secrets/evidence.key`, 32 raw random bytes, excluded from Git and ACL-restricted to the current Windows user/SYSTEM. Backend mounts it read-only. It is intentionally not printed. Back up this exact key separately in an encrypted offsite secret bundle: losing it makes uploaded evidence unrecoverable. Do not overwrite it to "rotate" existing objects; versioned re-encryption/key rotation needs a controlled migration.

The single-VPS overlay mounts `/srv/primevest/secrets/evidence.key` (or the configured data root), and requires `WEBAUTHN_RP_ID` and `WEBAUTHN_ORIGIN` matching the private HTTPS admin domain. Suggested Linux ownership root:1000, mode 0440. Keep admin behind VPN/IP allowlisting, and use app-specific MinIO permissions. Local development Compose is not the public production firewall topology.

The local pre-deployment dump is compressed/checksummed, NOT an encrypted offsite disaster-recovery backup. Production still requires offsite copies of PostgreSQL, encrypted objects and keys, restore verification, penetration/load tests, incident drills, real reserves and genuine release decisions.

## Verification and limitations

- 95 backend tests passed serially against the isolated `primevest_contract_verify` database, including funding concurrency, balance invariants, maker-checker, stale changes, release authority/revocation and HTTP authorization.
- 3 actual ClamAV/MinIO integration tests passed: encrypted round trip, anonymous read rejection, MIME/purpose rejection, harmless antivirus test-signature rejection and scanner outage.
- 31 Flutter tests passed; the funding retry tests also cover restart, concurrent submission and a gate closure after an uncertain request. Flutter analysis and backend/admin lint/type checks passed.
- Admin UI was visually checked using a temporary loopback-only test API and separate test database. Test operator was deactivated afterward. Actual physical-key enrollment and user-driven admin approval require the operator and were not fabricated by these tests.
- Backend/admin/worker were rebuilt and deployed locally; the updated debug app was installed on the connected M1K. Unlock the phone to review it. No release APK was produced for distribution.

Test commands: `RUN_DATABASE_INTEGRATION=true`, isolated `DATABASE_URL`, then `pnpm --filter @primevest/backend exec vitest run --no-file-parallelism --exclude test/evidence.integration.spec.ts`. Run evidence tests separately inside the backend Docker environment with `RUN_EVIDENCE_INTEGRATION=true` and the same isolated DB URL. This separation lets scanner tests use the private Docker network without opening its port publicly.

## Production deployment state — September 12, 2026

Historical snapshot only. The current Zettax deployment and Supabase project
are documented in `infrastructure/native-vps/README.md`; do not use the old
endpoints or database below for new deployment work.

- API: `https://primevest.metablaast.com`; host Nginx terminates TLS and proxies only to loopback port 4200. Public `/ready` and `/api/docs` return 404.
- Admin: `https://primevest-admin-bice.vercel.app`; the production CORS and WebAuthn origins match this exact hostname.
- PostgreSQL: Supabase project `xkghayxoclyqcudpphex`, private `primevest` schema. Fourteen Prisma migrations are applied. The Data API roles have no schema access. The application uses a separate limited login role and TLS certificate verification.
- VPS: systemd unit `primevest.service`; Redis, MinIO and ClamAV have no published ports. The API alone binds `127.0.0.1:4200`. The financial worker has no published port.
- Two production administrators exist: the operations owner and the restricted funding reviewer. Fresh random credentials are stored temporarily in root-only files under `/srv/primevest/secrets/*-admin-password`; retrieve them through SSH, store them in a password manager, then securely remove those two files.
- Runtime remains `DEMO_ONLY`. Real trading, deposits and withdrawals remain false. The live readiness check reports clean reconciliation but zero approved treasury statements, zero release approvals and all eleven release gates missing. An owner statement in chat is not stored as independent bank-statement evidence and is not duplicated into eleven signer records.
- Before activation, actual operators must submit and independently approve current treasury evidence, onboard release-authorized staff, approve every gate for release `2026-09-12.1` with at least five distinct authorized signers, and verify the readiness response is `ready: true`. Only then may the runtime flags be changed and the guarded financial smoke tests run.
