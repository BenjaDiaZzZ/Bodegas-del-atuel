#!/usr/bin/env bash
# =============================================================================
# run_db_tests.sh · TPI «Bodegas del Atuel»
# Corre los suites de reglas contra la base local y devuelve un código distinto
# de cero si falla al menos uno.
#
# Uso:
#   scripts/run_db_tests.sh            # base ya inicializada
#   scripts/run_db_tests.sh --reset    # recrea la base antes (reset_db.sh)
#   scripts/run_db_tests.sh --verbose  # muestra la salida completa de cada suite
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RESET=0
VERBOSE=0

for arg in "$@"; do
  case "$arg" in
    --reset)        RESET=1 ;;
    --verbose|-v)   VERBOSE=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f .env ]]; then
  echo "ERROR: falta .env. Copiá .env.example y ajustá los valores." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${POSTGRES_USER:?Falta POSTGRES_USER en .env}"
: "${POSTGRES_DB:?Falta POSTGRES_DB en .env}"

if [[ "$RESET" -eq 1 ]]; then
  ./scripts/reset_db.sh
fi

if ! docker compose ps --status running --services | grep -qx db; then
  echo "ERROR: el servicio db no está corriendo. Usá --reset o 'docker compose up -d db'." >&2
  exit 1
fi

status="$(docker inspect --format '{{.State.Health.Status}}' bodegas_del_atuel_db 2>/dev/null || echo unknown)"
if [[ "$status" != "healthy" ]]; then
  echo "ERROR: PostgreSQL no está healthy (estado actual: $status)." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL=0
PASSED=0
FAILED=0
FAILED_NAMES=()

run_sql_suite() {
  local file="$1"
  local name log rc

  name="$(basename "$file" .sql)"
  log="$TMP_DIR/$name.log"

  echo "== $name =="
  docker compose exec -T db psql \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -X -v ON_ERROR_STOP=1 -f - < "$file" > "$log" 2>&1
  rc=$?

  TOTAL=$((TOTAL + 1))
  if [[ "$rc" -eq 0 ]]; then
    PASSED=$((PASSED + 1))
    if [[ "$VERBOSE" -eq 1 ]]; then
      cat "$log"
    else
      grep -E 'NOTICE:  OK|^OK:' "$log" \
        | sed -E 's/^psql:<stdin>:[0-9]+: NOTICE:  /  PASS /; s/^OK:/  PASS/' || true
    fi
    echo "PASS $name"
  else
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$name")
    echo "FAIL $name (exit $rc)"
    grep -E 'ERROR:|FAIL|CONTEXT:' "$log" | tail -20 || tail -20 "$log"
  fi
}

run_concurrency_suite() {
  local name="test_004_concurrency"
  local log="$TMP_DIR/$name.log"
  local rc

  echo "== $name =="
  PGHOST=127.0.0.1 \
  PGPORT="${POSTGRES_PORT:-5432}" \
  PGUSER="$POSTGRES_USER" \
  PGPASSWORD="${POSTGRES_PASSWORD:?Falta POSTGRES_PASSWORD en .env}" \
  PGDATABASE="$POSTGRES_DB" \
    ./db/tests/test_004_concurrency.sh > "$log" 2>&1
  rc=$?

  TOTAL=$((TOTAL + 1))
  if [[ "$rc" -eq 0 ]]; then
    PASSED=$((PASSED + 1))
    if [[ "$VERBOSE" -eq 1 ]]; then
      cat "$log"
    else
      grep -E '^OK:|^RN-|stock_deposito=' "$log" | sed 's/^/  PASS /' || true
    fi
    echo "PASS $name"
  else
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$name")
    echo "FAIL $name (exit $rc)"
    tail -25 "$log"
  fi
}

run_sql_suite db/tests/test_007_roles.sql
run_sql_suite db/tests/test_006_vistas.sql
run_sql_suite db/tests/security_r001.sql
run_sql_suite db/tests/db_tests.sql
run_concurrency_suite

echo
echo "== Resumen =="
echo "Suites: $TOTAL | PASS: $PASSED | FAIL: $FAILED"
if [[ "$FAILED" -gt 0 ]]; then
  printf 'Fallaron: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
echo "OK: todas las reglas pasaron"
