#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=${ROOT_DIR:-/opt/primevest}
ENV_FILE=${ENV_FILE:-/etc/primevest/production.env}
DATA_ROOT=${PRIMEVEST_DATA_ROOT:-/srv/primevest}
LOCK_FILE=/run/lock/primevest-backup.lock
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
STAGING="${DATA_ROOT}/backups/${STAMP}"

if [[ "${DATA_ROOT}" != /srv/primevest ]]; then
  echo "PRIMEVEST_DATA_ROOT must resolve exactly to /srv/primevest." >&2
  exit 1
fi

cd "${ROOT_DIR}"
exec 9>"${LOCK_FILE}"
flock -n 9 || { echo "A PrimeVest backup is already running." >&2; exit 1; }
umask 077
install -d -m 0700 "${STAGING}/database" "${STAGING}/objects"

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.single-vps.yml)

backup_type=incr
if [[ $(date -u +%u) == 7 ]]; then
  backup_type=full
fi
"${COMPOSE[@]}" exec -T postgres pgbackrest --stanza=primevest check
"${COMPOSE[@]}" exec -T postgres pgbackrest --stanza=primevest --type="${backup_type}" backup

"${COMPOSE[@]}" exec -T postgres /bin/sh -eu -c '
  pg_dump \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --format custom \
  --compress 9 \
  --no-owner \
  --no-privileges
' >"${STAGING}/database/primevest.dump.partial"
mv "${STAGING}/database/primevest.dump.partial" "${STAGING}/database/primevest.dump"
sha256sum "${STAGING}/database/primevest.dump" >"${STAGING}/database/primevest.dump.sha256"

"${COMPOSE[@]}" run --rm --no-deps --entrypoint /bin/sh minio-init -eu -c '
  mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
  for bucket in "$MINIO_KYC_BUCKET" "$MINIO_PAYMENT_BUCKET" "$MINIO_REPORTS_BUCKET" "$MINIO_UPLOADS_BUCKET"; do
    install -d -m 0700 "/backup/'"${STAMP}"'/objects/$bucket"
    mc mirror --overwrite --remove "local/$bucket" "/backup/'"${STAMP}"'/objects/$bucket"
  done
'

cat >"${STAGING}/manifest.json" <<EOF
{"createdAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","host":"$(hostname)","format":"postgres-custom-plus-minio-mirror","encryptedOffsite":true}
EOF

if ! "${COMPOSE[@]}" --profile backup run --rm backup-tool snapshots >/dev/null 2>&1; then
  "${COMPOSE[@]}" --profile backup run --rm backup-tool init
fi
"${COMPOSE[@]}" --profile backup run --rm backup-tool backup "/backup/${STAMP}" --tag primevest-single-vps
"${COMPOSE[@]}" --profile backup run --rm backup-tool forget \
  --tag primevest-single-vps \
  --keep-daily 14 \
  --keep-weekly 12 \
  --keep-monthly 12 \
  --prune

find "${DATA_ROOT}/backups" -mindepth 1 -maxdepth 1 -type d -mtime +2 -exec rm -rf -- {} +
echo "Encrypted offsite backup completed: ${STAMP}"
