# PrimeVest single-VPS operations

This deployment is a hardened single failure domain for no more than 500
concurrent authenticated users. It is not highly available. The checked-in
configuration always validates a `DEMO_ONLY`/`MOCK` real-money boundary.

## Required host

- Ubuntu 24.04 LTS, 16 dedicated vCPUs, 64 GiB RAM and 500–600 GiB SSD/NVMe.
- A mounted block volume available at `/srv/primevest` before bootstrap.
- A static IP and provider firewall permitting `80/443` publicly and `22` only
  from the administrator CIDR.
- DNS names for API, admin and restricted Grafana status access.
- A SAN/wildcard TLS certificate mounted below
  `infrastructure/nginx/certs`; certificate renewal is an external host task.
- An encrypted, versioned S3-compatible repository outside the VPS. The
  PostgreSQL pgBackRest repository and Restic repository must use isolated
  prefixes or buckets and least-privilege credentials.

## Bootstrap

Run the bootstrap script from a trusted checkout on a fresh host. Use two
different public keys controlled by different people or storage mechanisms.

```bash
sudo ADMIN_CIDR=203.0.113.10/32 \
  DEPLOY_SSH_PUBLIC_KEY="ssh-ed25519 AAAA... deploy" \
  EMERGENCY_SSH_PUBLIC_KEY="ssh-ed25519 AAAA... breakglass" \
  bash infrastructure/scripts/bootstrap-single-vps.sh
```

Copy the repository to `/opt/primevest`. Copy
`infrastructure/env/production.env.example` to
`/etc/primevest/production.env`, replace every placeholder, set owner
`root:root`, and set mode `0600`. Passwords must be independently generated;
URL components in database and Redis URLs must be percent encoded.

Create the offsite pgBackRest bucket before starting the stack. Keep the
pgBackRest cipher passphrase outside both the VPS snapshot and repository.

## Preflight and startup

From `/opt/primevest`:

```bash
pwsh infrastructure/scripts/validate-production-config.ps1 \
  -EnvFile /etc/primevest/production.env \
  -SingleVps \
  -TestNginx

sudo systemctl start primevest
sudo systemctl status primevest
docker compose \
  --env-file /etc/primevest/production.env \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  -f docker-compose.single-vps.yml ps
```

Startup order is PostgreSQL, pgBackRest stanza validation, database role
creation, schema migrations/seed, runtime grants, PgBouncer, MinIO private
bucket initialization, both API replicas, admin, Grafana and Nginx. Failure of
any mandatory dependency keeps the edge unavailable.

Only Nginx publishes host ports. Verify this after every change:

```bash
docker ps --format '{{.Names}} {{.Ports}}'
ss -lntp
```

## Database roles

- `POSTGRES_USER` is the locked-down bootstrap administrator and is never used
  by the application.
- `POSTGRES_MIGRATION_USER` owns the database schema and is used only by the
  one-shot migration job.
- `POSTGRES_APP_USER` has runtime DML/function access and connects through
  PgBouncer transaction pooling.
- `POSTGRES_MONITOR_USER` receives `pg_monitor` only and cannot read customer
  tables.

Role creation, password rotation and grants are idempotent. Application
containers wait for the post-migration grant job, so a fresh database and an
upgraded database follow the same dependency chain.

## Backup and recovery

PostgreSQL archives WAL continuously through pgBackRest. `archive_timeout=240s`
bounds otherwise-idle WAL archive delay. The daily backup timer runs an
incremental pgBackRest backup, a logical custom-format dump, private MinIO
bucket mirrors, checksums and an encrypted Restic upload. Sunday runs use a full
physical backup.

```bash
sudo systemctl start primevest-backup.service
sudo systemctl enable --now primevest-backup.timer
sudo systemctl list-timers primevest-backup.timer
sudo journalctl -u primevest-backup.service
```

A five-minute RPO is an objective, not a claim based only on configuration.
Before launch, stop database writes in staging, restore the latest full backup
plus WAL into a clean VPS, and record the oldest lost committed transaction and
total recovery time. Launch fails if measured RPO exceeds five minutes or RTO
exceeds thirty minutes.

Restores must target a new database/data directory. Never test a restore by
overwriting production. Verify migrations, balanced journals, wallet
projections, orders, positions, outbox continuity, MinIO object checksums and
security/audit history before declaring recovery successful.

## Monitoring and alert delivery

Prometheus collects host, container, PostgreSQL and Redis metrics. Loki receives
Docker JSON logs through Promtail. Grafana is reachable only at the restricted
status hostname. Configure Alertmanager with two independent operator channels
before production; the checked-in receiver intentionally delivers nowhere so
missing alert configuration is visible during release review.

Application-level metrics still need to cover ledger imbalance, outbox age,
matching sequence, provider staleness, reconciliation breaks, authentication
replay, dealer exposure and withdrawals before real-money activation.

## Deployment

Run `infrastructure/scripts/deploy-single-vps.sh` from the host. The deployment
validates Compose, builds images, runs the migration job, starts both APIs,
waits for health, then starts the complete stack. Financial contract or engine
changes require maintenance mode and a reconciliation result before reopening.

The current script provides health-gated API replacement on one host; it cannot
protect against VPS, disk, kernel, Docker daemon, datacenter or provider-account
failure.

## Mandatory real-money blockers

Do not change `COMPLIANCE_MODE`, `EXECUTION_PROVIDER`, or real-money flags until
all production modules and external approvals listed in
`COMPLIANCE_GATES.md` are independently verified. In particular, the repository
does not yet contain an approved execution provider, HSM/MPC custody, official
payment adapter, completed KYC/AML workflow, principal-dealer controls or a
production matching engine. Infrastructure readiness does not satisfy those
requirements.
