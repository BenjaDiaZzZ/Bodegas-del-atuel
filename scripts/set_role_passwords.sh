#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: falta .env. Copiá .env.example y ajustá los valores:" >&2
  echo "  cp .env.example .env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${POSTGRES_USER:?Falta POSTGRES_USER en .env}"
: "${POSTGRES_DB:?Falta POSTGRES_DB en .env}"
: "${DB_PASSWORD:?Falta DB_PASSWORD en .env}"
: "${REPORTE_RO_PASSWORD:?Falta REPORTE_RO_PASSWORD en .env}"

if ! docker compose ps --status running --services | grep -qx "db"; then
  echo "ERROR: el servicio db no está corriendo." >&2
  echo "  docker compose up -d db" >&2
  exit 1
fi

echo "Asignando contraseñas a app_rw y reporte_ro desde .env..."
docker compose exec -T db psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -v ON_ERROR_STOP=1 \
  -v app_rw_password="$DB_PASSWORD" \
  -v reporte_ro_password="$REPORTE_RO_PASSWORD" <<'SQL'
ALTER ROLE app_rw WITH LOGIN PASSWORD :'app_rw_password';
ALTER ROLE reporte_ro WITH LOGIN PASSWORD :'reporte_ro_password';
SQL

echo "Contraseñas actualizadas."
