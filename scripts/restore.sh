#!/usr/bin/env bash
# =============================================================================
# restore.sh · TPI «Bodegas del Atuel» · 3.9
#
# Restaura un dump generado por backup.sh en una base distinta de la de
# origen, reaplica los privilegios de 007_roles.sql y verifica que los
# conteos de filas coincidan con el manifiesto del backup.
#
# Uso:
#   ./scripts/restore.sh --db bodegas_del_atuel_restore
#   ./scripts/restore.sh --db prueba_restore --dump backups/dump_completo.sql.gz
#   ./scripts/restore.sh --db prueba_restore --recreate
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

DUMP="backups/dump_completo.sql.gz"
TARGET_DB=""
RECREATE=0

usage() {
  cat <<'EOF'
Uso: scripts/restore.sh --db BASE_DESTINO [opciones]

  -d, --db BASE          Base destino (obligatoria y distinta de POSTGRES_DB).
  -f, --dump RUTA        Dump .sql.gz a restaurar (default: backups/dump_completo.sql.gz).
      --recreate         Borra y recrea la base destino si ya existe.
  -h, --help             Muestra esta ayuda.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--db)      TARGET_DB="$2"; shift 2 ;;
    -f|--dump)    DUMP="$2"; shift 2 ;;
    --recreate)   RECREATE=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$TARGET_DB" ]]; then
  echo "ERROR: falta --db con la base destino." >&2
  usage >&2
  exit 1
fi

if [[ ! "$TARGET_DB" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "ERROR: nombre de base inválido: $TARGET_DB" >&2
  echo "  Solo letras, números y guion bajo; debe empezar con letra o guion bajo." >&2
  exit 1
fi

if [[ ! -f "$DUMP" ]]; then
  echo "ERROR: no existe el dump: $DUMP" >&2
  echo "  Generá uno con: ./scripts/backup.sh" >&2
  exit 1
fi

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

if [[ "$TARGET_DB" == "$POSTGRES_DB" ]]; then
  echo "ERROR: la base destino debe ser distinta de la de origen ($POSTGRES_DB)." >&2
  exit 1
fi

if ! docker compose ps --status running --services | grep -x "db" > /dev/null; then
  echo "ERROR: el servicio db no está corriendo." >&2
  echo "  docker compose up -d db" >&2
  exit 1
fi

COUNTS="${DUMP}.counts"
if [[ ! -f "$COUNTS" ]]; then
  echo "ADVERTENCIA: no existe el manifiesto $COUNTS; no se verificarán conteos." >&2
fi

db_exists() {
  docker compose exec -T db psql \
    -U "$POSTGRES_USER" \
    -d postgres \
    -At \
    -v ON_ERROR_STOP=1 \
    -c "SELECT 1 FROM pg_database WHERE datname = '$TARGET_DB'" \
    | grep -x "1" > /dev/null
}

if db_exists; then
  if [[ "$RECREATE" -eq 0 ]]; then
    echo "ERROR: la base $TARGET_DB ya existe. Usá --recreate para borrarla y recrearla." >&2
    exit 1
  fi
  echo "== Eliminando base destino existente: $TARGET_DB =="
  docker compose exec -T db dropdb \
    -U "$POSTGRES_USER" \
    --force \
    --if-exists \
    "$TARGET_DB"
fi

echo "== Creando base destino: $TARGET_DB =="
docker compose exec -T db createdb -U "$POSTGRES_USER" "$TARGET_DB"

echo "== Restaurando $(basename "$DUMP") en $TARGET_DB =="
gunzip -c "$DUMP" | docker compose exec -T db psql \
  -U "$POSTGRES_USER" \
  -d "$TARGET_DB" \
  -v ON_ERROR_STOP=1 \
  -q \
  -o /dev/null

echo "== Reaplicando privilegios: 007_roles.sql =="
docker compose exec -T db psql \
  -U "$POSTGRES_USER" \
  -d "$TARGET_DB" \
  -v ON_ERROR_STOP=1 \
  -q \
  -o /dev/null < db/migrations/007_roles.sql

if [[ -f "$COUNTS" ]]; then
  COUNT_SQL="
SELECT c.relname || '|' ||
       (xpath('/row/c/text()',
              query_to_xml(format('SELECT count(*) AS c FROM public.%I', c.relname),
                           false, true, '')))[1]::text
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind = 'r'
 ORDER BY c.relname;
"
  TARGET_COUNTS="$(mktemp "${TMPDIR:-/tmp}/restore-counts.XXXXXX")"
  trap 'rm -f "$TARGET_COUNTS"' EXIT

  docker compose exec -T db psql \
    -U "$POSTGRES_USER" \
    -d "$TARGET_DB" \
    -At -F '|' \
    -v ON_ERROR_STOP=1 \
    -c "$COUNT_SQL" > "$TARGET_COUNTS"

  if diff -u "$COUNTS" "$TARGET_COUNTS" > /dev/null; then
    echo "OK: los conteos de $TARGET_DB coinciden con el manifiesto ($(wc -l < "$COUNTS" | tr -d ' ') tablas)."
  else
    echo "FAIL: los conteos de $TARGET_DB NO coinciden con el manifiesto." >&2
    diff -u "$COUNTS" "$TARGET_COUNTS" >&2 || true
    exit 1
  fi

  trap - EXIT
  rm -f "$TARGET_COUNTS"
fi

echo "== Restauración completa: $TARGET_DB =="
