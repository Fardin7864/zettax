#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=${ROOT_DIR:-/opt/primevest}
ENV_FILE=${ENV_FILE:-/etc/primevest/production.env}
cd "${ROOT_DIR}"

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.single-vps.yml)

"${COMPOSE[@]}" config --quiet
API_DOMAIN=$("${COMPOSE[@]}" config --format json | jq -r '.services.nginx.environment.API_DOMAIN')
[[ -n "${API_DOMAIN}" && "${API_DOMAIN}" != null ]] || { echo "API_DOMAIN is missing" >&2; exit 1; }
"${COMPOSE[@]}" build postgres backend admin
"${COMPOSE[@]}" run --rm migrate
"${COMPOSE[@]}" up -d --no-deps backend backend-b

for service in backend backend-b; do
  container_id=$("${COMPOSE[@]}" ps -q "${service}")
  [[ -n "${container_id}" ]] || { echo "${service} did not start" >&2; exit 1; }
  for _ in $(seq 1 60); do
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "${container_id}")
    [[ "${status}" == healthy ]] && break
    [[ "${status}" == unhealthy ]] && { docker logs "${container_id}"; exit 1; }
    sleep 2
  done
  [[ "$(docker inspect --format '{{.State.Health.Status}}' "${container_id}")" == healthy ]] || exit 1
done

"${COMPOSE[@]}" up -d --remove-orphans
"${COMPOSE[@]}" ps
curl --fail --silent --show-error --resolve "${API_DOMAIN}:443:127.0.0.1" "https://${API_DOMAIN}/health" >/dev/null
echo "Deployment healthy. Financial gates remain controlled by the validated environment configuration."
