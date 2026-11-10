#!/usr/bin/env bash
# =============================================================================
# set_role_passwords.sh · TPI «Bodegas del Atuel»
#
# Asigna LOGIN y contraseña a los roles de aplicación desde .env.
#
# Uso local (Docker Compose):
#   ./scripts/set_role_passwords.sh
#
# Uso en la nube (conecta como administrador y TLS):
#   ./scripts/set_role_passwords.sh --cloud
#
# Uso contra una URL cualquiera:
#   ./scripts/set_role_passwords.sh --db-url "postgresql://bda_owner@host:puerto/base?sslmode=require"
#
# Las contraseñas se leen de .env y nunca se escriben en el repositorio.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

MODE="docker"
DB_URL=""

usage() {
  cat <<'EOF'
Uso: scripts/set_role_passwords.sh [opciones]

  (sin opciones)   Usa Docker Compose y POSTGRES_USER/POSTGRES_DB de .env.
  --cloud          Conecta a CLOUD_DB_* como administrador con TLS (sslmode=require).
  --db-url URL     Conecta a la URL indicada; el usuario debe poder ALTER ROLE.
  -h, --help       Muestra esta ayuda.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)    MODE="cloud"; shift ;;
    --db-url)
      [[ $# -ge 2 ]] || { echo "Falta la URL para --db-url." >&2; usage >&2; exit 1; }
      MODE="url"; DB_URL="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ! -f .env ]]; then
  echo "ERROR: falta .env. Copiá .env.example y ajustá los valores:" >&2
  echo "  cp .env.example .env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${DB_PASSWORD:?Falta DB_PASSWORD en .env}"
: "${REPORTE_RO_PASSWORD:?Falta REPORTE_RO_PASSWORD en .env}"

SQL="$(cat <<'EOF'
ALTER ROLE app_rw WITH LOGIN PASSWORD :'app_rw_password';
ALTER ROLE reporte_ro WITH LOGIN PASSWORD :'reporte_ro_password';
EOF
)"

if [[ "$MODE" == "docker" ]]; then
  : "${POSTGRES_USER:?Falta POSTGRES_USER en .env}"
  : "${POSTGRES_DB:?Falta POSTGRES_DB en .env}"

  if ! docker compose ps --status running --services | grep -x "db" > /dev/null; then
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
    -v reporte_ro_password="$REPORTE_RO_PASSWORD" <<< "$SQL"
elif [[ "$MODE" == "cloud" ]]; then
  : "${CLOUD_DB_HOST:?Falta CLOUD_DB_HOST en .env}"
  : "${CLOUD_DB_PORT:?Falta CLOUD_DB_PORT en .env}"
  : "${CLOUD_DB_NAME:?Falta CLOUD_DB_NAME en .env}"
  : "${CLOUD_ADMIN_USER:?Falta CLOUD_ADMIN_USER en .env}"
  : "${CLOUD_ADMIN_PASSWORD:?Falta CLOUD_ADMIN_PASSWORD en .env}"
  : "${BDA_OWNER_PASSWORD:?Falta BDA_OWNER_PASSWORD en .env}"
  CLOUD_DB_SSLMODE="${CLOUD_DB_SSLMODE:-require}"

  echo "Asignando contraseñas en ${CLOUD_DB_HOST}/${CLOUD_DB_NAME} como ${CLOUD_ADMIN_USER}..."
  PGPASSWORD="$CLOUD_ADMIN_PASSWORD" PGSSLMODE="$CLOUD_DB_SSLMODE" \
    psql -h "$CLOUD_DB_HOST" -p "$CLOUD_DB_PORT" -U "$CLOUD_ADMIN_USER" -d "$CLOUD_DB_NAME" \
      -v ON_ERROR_STOP=1 \
      -v owner_password="$BDA_OWNER_PASSWORD" \
      -v app_rw_password="$DB_PASSWORD" \
      -v reporte_ro_password="$REPORTE_RO_PASSWORD" <<'SQL'
ALTER ROLE bda_owner WITH LOGIN PASSWORD :'owner_password';
ALTER ROLE app_rw WITH LOGIN PASSWORD :'app_rw_password';
ALTER ROLE reporte_ro WITH LOGIN PASSWORD :'reporte_ro_password';
SQL
else
  echo "Asignando contraseñas mediante --db-url..."
  psql "$DB_URL" \
    -v ON_ERROR_STOP=1 \
    -v app_rw_password="$DB_PASSWORD" \
    -v reporte_ro_password="$REPORTE_RO_PASSWORD" <<< "$SQL"
fi

echo "Contraseñas actualizadas."
