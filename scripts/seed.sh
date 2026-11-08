#!/usr/bin/env bash
# =============================================================================
# seed.sh · TPI «Bodegas del Atuel»
# Ejecuta el seed determinístico y las consultas de control.
#
# Uso:
#   scripts/seed.sh --scale small --fecha-base 2026-01-01
#   scripts/seed.sh --scale full --fecha-base 2026-01-01 --benchmark
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
SCALE="small"
FECHA_BASE="$(date +%Y-%m-%d)"
BENCHMARK=""
DB_URL="${DATABASE_URL:-postgresql://bodegas@localhost:5433/bodegas_del_atuel}"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scale)      SCALE="$2"; shift 2 ;;
        --fecha-base) FECHA_BASE="$2"; shift 2 ;;
        --benchmark)  BENCHMARK="--benchmark"; shift ;;
        --db-url)     DB_URL="$2"; shift 2 ;;
        *) echo "Opción desconocida: $1" >&2; exit 1 ;;
    esac
done

PYTHON="${ROOT_DIR}/.venv/bin/python"
[[ -x "$PYTHON" ]] || PYTHON="python3"

echo "== Ejecutando seed (scale=${SCALE}, fecha-base=${FECHA_BASE}) =="
"$PYTHON" "${ROOT_DIR}/db/seed/seed.py" \
    --scale "$SCALE" \
    --fecha-base "$FECHA_BASE" \
    --db-url "$DB_URL" \
    $BENCHMARK

if [[ -z "$BENCHMARK" ]]; then
    echo ""
    echo "== Ejecutando controles =="
    psql "$DB_URL" -f "${ROOT_DIR}/db/seed/controles.sql"
fi

echo "== Listo =="
