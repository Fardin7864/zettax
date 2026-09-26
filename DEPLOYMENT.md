# Deployment

The current Zettax VPS deployment at `187.126.114.59` runs without Docker.
Its Node services, Nginx sites, Supabase settings, and certificate renewal are
documented in [native VPS operations](infrastructure/native-vps/README.md).
The Compose instructions below are retained for reference and are not used on
this host.

## Local integrated environment

The withdrawal-verification, community, comment-reply, and prediction APIs
require the committed `20260926180000_withdrawal_verification`,
`20260926190000_community`, `20260926223000_community_replies`, and
`20260926230000_prediction_questions` migrations. Apply them before installing
a mobile build that uses these screens.
Set `MFA_ENCRYPTION_KEY` to a unique 32-byte hex value in the protected backend
environment. Configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`,
and `SMTP_FROM` only after the mailbox and sender domain are verified. The
password belongs in the protected environment, never in source control or the
mobile build. Email codes remain unavailable until SMTP is configured. Image
posts also require the existing private evidence storage and scanner. The
The Prediction tab supports objective crypto price questions created by Zettax
or its users, Yes/No positions, and a separate demo pool. The financial worker
keeps one open BTC and ETH question available, each with a one-hour expiry and
a target drawn from the archived price. The existing
price-direction screen remains available. Winners receive their original
stakes plus a proportional share of losing stakes, rounded to cents; when no
one selects the winning side, all stakes are refunded. Settlement uses the
last archived Binance one-second close before the stated UTC expiry. The
financial worker must be running to settle expired questions. Real-money
positions are disabled by default; `ENABLE_PREDICTIONS`,
`ENABLE_REAL_TRADING`, `PREDICTION_REAL_APPROVAL_REFERENCE`, production mode,
and the existing release readiness controls are all required before they can
be accepted. Complete legal, compliance, treasury, security, and operations
review before enabling them. These questions are Zettax-managed and do not
create third-party prediction-market contracts.

Local development uses `docker-compose.yml` and intentionally publishes the API, admin, PostgreSQL, Redis, and MinIO ports to the host. Its credentials and HTTP endpoints are development-only.

```powershell
Copy-Item .env.example .env
docker compose up -d --build
docker compose ps
Invoke-RestMethod http://localhost:3000/health
Invoke-RestMethod http://localhost:3000/ready
```

The backend waits for PostgreSQL, applies committed Prisma migrations, runs the idempotent system seed, then starts. `/health` is process liveness. `/ready` currently checks TCP connectivity to PostgreSQL, Redis, and MinIO; it is not evidence of authenticated dependency operations, market-provider availability, worker health, or financial reconciliation.

## Production configuration

Production uses both Compose files. Start by copying the dedicated template to a protected path outside source control and replacing every placeholder:

The Zettax production template uses `api.zettax.app` for the mobile API,
`admin.zettax.app` for the operations console, and `status.zettax.app` for
monitoring. The apex `zettax.app` is reserved for the public site; this
repository does not currently serve a public site at that hostname. Create the
corresponding DNS records and a certificate covering the configured hosts
before deployment.

```powershell
Copy-Item infrastructure/env/production.env.example C:/secure/primevest-production.env
```

Required operator-supplied values include:

- PostgreSQL database, user, password, and a matching URL-encoded `DATABASE_URL`;
- Redis password and authenticated `REDIS_URL`;
- MinIO root credentials plus a separately provisioned application access key, secret, and private bucket;
- unique JWT access and refresh secrets of at least 32 random characters;
- API/admin domains, exact HTTPS CORS origins, public HTTPS API URL, and an admin VPN/office CIDR;
- certificate and private-key paths inside the Nginx container's `/etc/letsencrypt` read-only mount.

Validate the rendered topology before every deployment:

```powershell
./infrastructure/scripts/validate-production-config.ps1 `
  -EnvFile C:/secure/primevest-production.env
```

Add `-TestNginx` only after the referenced certificate files exist under `infrastructure/nginx/certs`. It starts an ephemeral Nginx validation container and runs `nginx -t`; it does not start the application.

Then deploy:

```powershell
docker compose `
  --env-file C:/secure/primevest-production.env `
  -f docker-compose.yml `
  -f docker-compose.prod.yml `
  up -d --build
```

The production overlay:

- resets every inherited host port and publishes only Nginx on 80/443;
- separates public edge, application, and internal data networks;
- requires database, Redis, MinIO, JWT, domain, CORS, API URL, admin CIDR, and TLS configuration;
- runs long-lived services as non-root with read-only root filesystems, dropped capabilities, `no-new-privileges`, bounded processes/resources, writable tmpfs paths, and rotated Docker logs;
- uses a short-lived, network-disabled volume initializer with only `CHOWN`/`FOWNER` capabilities before the non-root data services start;
- builds `NEXT_PUBLIC_API_URL` into the admin artifact as required by Next.js rather than assuming a runtime environment variable can rewrite the browser bundle;
- redirects HTTP to HTTPS, terminates TLS 1.2/1.3, emits HSTS/security headers, rate-limits requests, forwards request/proxy metadata, blocks public Swagger, and restricts the admin host to `ADMIN_ALLOW_CIDR`.

Use a SAN or wildcard certificate valid for both configured hosts, or split the Nginx template into per-host certificate settings. Certificate issuance/renewal is deliberately external to this repository: mount only the required certificate tree read-only and automate renewal plus an audited Nginx reload on the host. Do not expose authentication before a valid certificate and HTTPS smoke test exist.

## Single-VPS production topology

For the explicitly accepted single-host deployment, add
`docker-compose.single-vps.yml` after the base and production files. This adds
two API replicas, one-shot migrations, PgBouncer, separate database roles,
private MinIO bucket initialization, ClamAV, continuous encrypted pgBackRest WAL
archiving, Restic offsite snapshots, Prometheus, Alertmanager, Grafana, Loki,
Promtail and host/container/database/cache exporters. All state remains within
one host failure domain even though process-level replicas are present.

Use `-SingleVps` when validating:

```powershell
./infrastructure/scripts/validate-production-config.ps1 `
  -EnvFile C:/secure/primevest-production.env `
  -SingleVps `
  -TestNginx
```

The Ubuntu provisioning, service startup, backup, recovery and operational
workflow is documented in [single-VPS operations](docs/SINGLE_VPS_OPERATIONS.md).

## Demo-only production baseline

The checked-in production template intentionally retains:

```dotenv
COMPLIANCE_MODE=DEMO_ONLY
EXECUTION_PROVIDER=MOCK
ENABLE_REAL_TRADING=false
ENABLE_CRYPTO_TRADING=false
ENABLE_FOREX_TRADING=false
ENABLE_STOCK_TRADING=false
ENABLE_COMMODITY_TRADING=false
ENABLE_INDEX_TRADING=false
ENABLE_DEPOSITS=false
ENABLE_WITHDRAWALS=false
```

The validation script accepts only this fail-closed baseline. Infrastructure readiness, HTTPS, or a live display-data feed does not authorize real-money activity. Production approval still requires legal/compliance evidence, complete KYC/AML and admin controls, authorized payment operations, an approved execution adapter, reconciliation, incident response, monitoring, penetration testing, and independent release approval.

## Backup, checksum, and restore drill

Create a compressed PostgreSQL custom-format dump plus SHA-256 and JSON metadata sidecars:

```powershell
./infrastructure/scripts/backup-postgres.ps1 `
  -ComposeFiles docker-compose.yml,docker-compose.prod.yml `
  -EnvFile C:/secure/primevest-production.env `
  -DatabaseUser primevest `
  -DatabaseName primevest `
  -Destination D:/primevest-staging/backups `
  -RetentionDays 14
```

The backup is compressed and integrity-checkable but is not encrypted. Move it into encrypted, access-controlled off-host storage, record upload success, and protect/delete local staging according to the retention policy. Schedule the command externally with a locked-down service account and alert on missing dumps, checksum failures, age, size anomalies, and off-host replication failure.

Restore only into a new verification database; the script rejects the source database and an existing target, requires the checksum sidecar, and retains the restored database for inspection:

```powershell
./infrastructure/scripts/restore-postgres.ps1 `
  -BackupFile D:/primevest-staging/backups/primevest-primevest-YYYYMMDDTHHMMSSZ.dump `
  -ComposeFiles docker-compose.yml,docker-compose.prod.yml `
  -EnvFile C:/secure/primevest-production.env `
  -SourceDatabase primevest `
  -TargetDatabase primevest_restore_20260909
```

Automated verification checks that public tables exist, no migration is failed/rolled back, and no ledger transaction is unbalanced. A real drill must additionally run authentication, account/ledger reconciliation, funding state-machine, audit-history, application-version, MinIO-object, and recovery-time checks. PostgreSQL dumps alone do not back up MinIO objects, Redis operational state, certificates, environment secrets, or host configuration. Define encrypted backups and restore procedures for each required component, with documented RPO/RTO and periodic evidence.

## Market-data boundary

`TWELVE_DATA_API_KEY` is passed only to the backend. `TWELVE_DATA_DISPLAY_LICENSE_APPROVED` remains `false` until the operator verifies contractual display rights for that environment. The free/individual plan is development/evaluation-only for this project. Production display requires the appropriate business/display/redistribution agreement, attribution, exchange licences, permitted territories, retention limits, quota monitoring, and provider incident contact.

Market data never enables execution. Keep the real-money flags off and `EXECUTION_PROVIDER=MOCK` until the separate regulated-production approval is complete. See [market-data operations](docs/MARKET_DATA_OPERATIONS.md) and [compliance gates](docs/COMPLIANCE_GATES.md).
