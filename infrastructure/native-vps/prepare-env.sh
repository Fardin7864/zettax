#!/usr/bin/env bash
set -euo pipefail

base=/srv/zettax/shared/base.env
target=/srv/zettax/shared/production.env
key=/srv/zettax/secrets/evidence.key

test -s "$base"
test "$(stat -c %s "$key")" -eq 32
if test -e "$target"; then
  echo "Production environment already exists; keeping its secrets."
  exit 0
fi

umask 027
temporary=$(mktemp /srv/zettax/shared/production.env.XXXXXX)
trap 'rm -f "$temporary"' EXIT
cp -- "$base" "$temporary"
{
  printf '\n# Native Zettax VPS overrides\n'
  printf 'NODE_ENV=production\n'
  printf 'BACKEND_HOST=127.0.0.1\n'
  printf 'BACKEND_PORT=3000\n'
  printf 'NEXT_PUBLIC_API_URL=https://api.zettax.app/api/v1\n'
  printf 'CORS_ORIGINS=https://admin.zettax.app\n'
  printf 'WEBAUTHN_RP_ID=admin.zettax.app\n'
  printf 'WEBAUTHN_ORIGIN=https://admin.zettax.app\n'
  printf 'HEALTH_REQUIRE_REDIS=false\n'
  printf 'HEALTH_REQUIRE_OBJECT_STORAGE=false\n'
  printf 'EVIDENCE_ENCRYPTION_KEY_FILE=%s\n' "$key"
  printf 'JWT_ACCESS_SECRET=%s\n' "$(openssl rand -hex 32)"
  printf 'JWT_REFRESH_SECRET=%s\n' "$(openssl rand -hex 32)"
  printf 'RELEASE_VERSION=zettax-20260923-01\n'
} >> "$temporary"
chown root:zettax "$temporary"
chmod 0640 "$temporary"
mv -- "$temporary" "$target"
trap - EXIT
echo "Production environment prepared."
