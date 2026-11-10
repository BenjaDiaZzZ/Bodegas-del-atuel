#!/usr/bin/env bash
# =============================================================================
# seed_cloud.sh · TPI «Bodegas del Atuel» — 8.4
#
# Carga el seed determinístico y ejecuta los controles contra la base
# PostgreSQL en Aiven (o cualquier instancia cloud configurada en .env).
#
# Requiere en .env (ya configurado por migrate.sh / 8.2):
#   CLOUD_DB_HOST, CLOUD_DB_PORT, CLOUD_DB_NAME
#   CLOUD_DB_SSLMODE (default: require)
#   BDA_OWNER_PASSWORD
#
# Uso:
#   scripts/seed_cloud.sh                    # scale small, fecha-base hoy, limpia antes
#   scripts/seed_cloud.sh --scale full       # volumen completo
#   scripts/seed_cloud.sh --fecha-base 2026-01-01
#   scripts/seed_cloud.sh --no-clean         # no limpia antes de cargar
#   scripts/seed_cloud.sh --benchmark        # solo benchmark, sin carga
#
# IMPORTANTE: ejecutar con las credenciales reales en .env. El script
# nunca muestra contraseñas ni las imprime en logs.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# Cargar .env si existe
if [[ -f .env ]]; then
    set -a
    # shellcheck source=/dev/null
    . ./.env
    set +a
fi

# Defaults
SCALE="small"
FECHA_BASE="$(date +%Y-%m-%d)"
BENCHMARK=""
CLEAN="true"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scale)      SCALE="$2"; shift 2 ;;
        --fecha-base) FECHA_BASE="$2"; shift 2 ;;
        --benchmark)  BENCHMARK="--benchmark"; shift ;;
        --clean)      CLEAN="true"; shift ;;
        --no-clean)   CLEAN="false"; shift ;;
        -h|--help)    sed -n '3,20p' "$0"; exit 0 ;;
        *) echo "Opción desconocida: $1" >&2; exit 1 ;;
    esac
done

# Validar variables cloud
: "${CLOUD_DB_HOST:?Falta CLOUD_DB_HOST en .env}"
: "${CLOUD_DB_PORT:?Falta CLOUD_DB_PORT en .env}"
: "${CLOUD_DB_NAME:?Falta CLOUD_DB_NAME en .env}"
: "${BDA_OWNER_PASSWORD:?Falta BDA_OWNER_PASSWORD en .env}"

CLOUD_DB_SSLMODE="${CLOUD_DB_SSLMODE:-require}"

# Construir URL para psycopg (el seed usa psycopg3)
DB_URL="postgresql://bda_owner:${BDA_OWNER_PASSWORD}@${CLOUD_DB_HOST}:${CLOUD_DB_PORT}/${CLOUD_DB_NAME}?sslmode=${CLOUD_DB_SSLMODE}"

PYTHON="${ROOT_DIR}/.venv/bin/python"
[[ -x "$PYTHON" ]] || PYTHON="python3"

echo "== Seed cloud: bda_owner@${CLOUD_DB_HOST}:${CLOUD_DB_PORT}/${CLOUD_DB_NAME} =="
echo "== Scale: ${SCALE} | Fecha base: ${FECHA_BASE} =="

if [[ -z "$BENCHMARK" && "$CLEAN" == "true" ]]; then
    echo "== Limpiando tablas antes de cargar =="
    PGPASSWORD="$BDA_OWNER_PASSWORD" PGSSLMODE="$CLOUD_DB_SSLMODE" \
        psql -h "$CLOUD_DB_HOST" -p "$CLOUD_DB_PORT" -U bda_owner -d "$CLOUD_DB_NAME" \
        -c "TRUNCATE TABLE public.analisis_calidad, public.auditoria_precio, public.bodega, public.cepa, public.cliente, public.composicion, public.comprobante, public.distribuidor, public.empleado, public.exportador, public.finca, public.ingreso, public.localidad, public.lote_uva, public.maridaje, public.parcela, public.permiso_exportacion, public.renglon_comprobante, public.renglon_ingreso, public.renglon_transferencia, public.sala, public.socio, public.stock_deposito, public.stock_sala, public.transferencia, public.transportista, public.transportista_localidad, public.vino, public.vino_maridaje CASCADE;"
fi

"$PYTHON" "${ROOT_DIR}/db/seed/seed.py" \
    --scale "$SCALE" \
    --fecha-base "$FECHA_BASE" \
    --db-url "$DB_URL" \
    $BENCHMARK

if [[ -z "$BENCHMARK" ]]; then
    echo ""
    echo "== Controles =="
    PGPASSWORD="$BDA_OWNER_PASSWORD" PGSSLMODE="$CLOUD_DB_SSLMODE" \
        psql -h "$CLOUD_DB_HOST" -p "$CLOUD_DB_PORT" -U bda_owner -d "$CLOUD_DB_NAME" \
        -f "${ROOT_DIR}/db/seed/controles.sql"
fi

echo ""
echo "== Listo =="
