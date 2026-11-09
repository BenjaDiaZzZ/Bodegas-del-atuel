#!/usr/bin/env bash
# =============================================================================
# backup.sh · TPI «Bodegas del Atuel» · 3.9
#
# Genera un dump lógico comprimido de la base local y un manifiesto con el
# conteo exacto de filas por tabla. El dump es portable a otra base porque
# se toma con --no-owner y --no-privileges; los privilegios se reaplican con
# 007_roles.sql en restore.sh.
#
# Uso:
#   ./scripts/backup.sh
#   ./scripts/backup.sh --output backups/dump_completo.sql.gz
#   ./scripts/backup.sh -o /tmp/respaldo.sql.gz
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

OUTPUT="backups/dump_completo.sql.gz"

usage() {
  cat <<'EOF'
Uso: scripts/backup.sh [--output RUTA]

  -o, --output RUTA   Archivo .sql.gz de salida (default: backups/dump_completo.sql.gz).
                      El manifiesto de conteos se guarda en RUTA.counts.
  -h, --help          Muestra esta ayuda.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUTPUT="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
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

: "${POSTGRES_USER:?Falta POSTGRES_USER en .env}"
: "${POSTGRES_DB:?Falta POSTGRES_DB en .env}"

if ! docker compose ps --status running --services | grep -x "db" > /dev/null; then
  echo "ERROR: el servicio db no está corriendo." >&2
  echo "  docker compose up -d db" >&2
  exit 1
fi

COUNTS="${OUTPUT}.counts"
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

mkdir -p "$(dirname "$OUTPUT")"
DUMP_TMP="$(mktemp "${OUTPUT}.XXXXXX")"
COUNTS_TMP="$(mktemp "${COUNTS}.XXXXXX")"
cleanup() { rm -f "$DUMP_TMP" "$COUNTS_TMP"; }
trap cleanup EXIT

echo "== Backup de ${POSTGRES_DB} =="
if ! docker compose exec -T db pg_dump \
      -U "$POSTGRES_USER" \
      -d "$POSTGRES_DB" \
      --no-owner \
      --no-privileges \
      --clean \
      --if-exists \
      --encoding=UTF8 \
      | gzip -9 > "$DUMP_TMP"; then
  echo "ERROR: pg_dump falló; no se generó el respaldo." >&2
  exit 1
fi

echo "== Conteos por tabla =="
docker compose exec -T db psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -At -F '|' \
  -v ON_ERROR_STOP=1 \
  -c "$COUNT_SQL" > "$COUNTS_TMP"

mv "$DUMP_TMP" "$OUTPUT"
mv "$COUNTS_TMP" "$COUNTS"
trap - EXIT

echo "Dump:    $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo "Conteos: $COUNTS ($(wc -l < "$COUNTS" | tr -d ' ') tablas)"
