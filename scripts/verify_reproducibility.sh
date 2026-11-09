#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCALE=small
DATE_A="$(date +%F)"
DATE_B=""
KEEP=false
TMP_DIR=""
CONTAINERS=()

usage() {
  cat <<'HELP'
Uso: scripts/verify_reproducibility.sh [opciones]

Compara dos cargas del seed en PostgreSQL efímeros y ejecuta los controles.

Opciones:
  --scale {small,full}       Escala del seed (por defecto: small).
  --fecha-base YYYY-MM-DD    Fecha de la corrida A (por defecto: hoy).
  --fecha-base-b YYYY-MM-DD  Fecha de la corrida B (por defecto: igual a A).
  --keep                     Conserva los contenedores para depuración.
  --help                     Muestra esta ayuda.
HELP
}

while (($#)); do
  case "$1" in
    --scale) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; SCALE="$2"; shift 2 ;;
    --fecha-base) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; DATE_A="$2"; shift 2 ;;
    --fecha-base-b) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; DATE_B="$2"; shift 2 ;;
    --keep) KEEP=true; shift ;;
    --help) usage; exit 0 ;;
    *) printf 'Opción desconocida: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
DATE_B="${DATE_B:-$DATE_A}"
[[ "$SCALE" == small || "$SCALE" == full ]] || { printf 'Escala inválida: %s\n' "$SCALE" >&2; exit 2; }
for value in "$DATE_A" "$DATE_B"; do
  date -d "$value" +%F >/dev/null 2>&1 && [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { printf 'Fecha inválida: %s\n' "$value" >&2; exit 2; }
done

cleanup() {
  local status=$?
  if [[ "$KEEP" != true ]]; then
    for name in "${CONTAINERS[@]}"; do docker rm -f "$name" >/dev/null 2>&1 || true; done
  fi
  [[ -z "$TMP_DIR" ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT

cd "$ROOT_DIR"
PYTHON="$ROOT_DIR/.venv/bin/python"
if [[ ! -x "$PYTHON" ]] || ! "$PYTHON" -c 'import psycopg, faker' >/dev/null 2>&1; then
  python3 -m venv .venv
  "$PYTHON" -m pip install -r db/seed/requirements.txt
fi
TMP_DIR="$(mktemp -d)"

run_one() {
  local tag="$1" base_date="$2" name="bodegas_repro_$1" port ready=0 started ended controls_file hash_file
  CONTAINERS+=("$name")
  started=$(date +%s)
  docker run --rm -d --name "$name" -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=test -p 127.0.0.1:0:5432 postgres:16-alpine >/dev/null
  port="$(docker inspect -f '{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' "$name")"
  for _ in {1..60}; do
    if docker exec "$name" pg_isready -U test -d test >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
  done
  [[ $ready -eq 1 ]] || { printf 'PostgreSQL %s no estuvo listo después de 60 intentos.\n' "$name" >&2; return 1; }
  for migration in "$ROOT_DIR"/db/migrations/00[1-7]_*.sql; do
    docker exec -i "$name" psql -U test -d test -v ON_ERROR_STOP=1 < "$migration"
  done
  "$PYTHON" db/seed/seed.py --scale "$SCALE" --fecha-base "$base_date" --db-url "postgresql://test:test@127.0.0.1:$port/test"
  docker exec -i "$name" psql -U test -d test -v ON_ERROR_STOP=1 < db/migrations/008_indices.sql
  docker exec "$name" psql -U test -d test -v ON_ERROR_STOP=1 -c ANALYZE

  hash_file="$TMP_DIR/$tag.tsv"
  docker exec "$name" psql -U test -d test -At -c "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename" | while IFS= read -r table; do
    docker exec "$name" psql -U test -d test -At -F $'\t' -c "SELECT '$table', count(*), md5(coalesce(string_agg(r::text, chr(10) ORDER BY r::text), '')) FROM public.\"$table\" r"
  done > "$hash_file"
  printf 'Tablas públicas incluidas en %s: %s\n' "$tag" "$(wc -l < "$hash_file")"

  controls_file="$TMP_DIR/controles-$tag.tsv"
  docker exec -i "$name" psql -U test -d test -v ON_ERROR_STOP=1 -At -F $'\t' < db/seed/controles.sql | tee "$controls_file"
  local control errors failures=0 checked_controls=0
  while IFS=$'\t' read -r control errors; do
    if [[ "$control" == conteo:* ]]; then
      continue
    fi
    ((checked_controls+=1))
    if [[ "$errors" != 0 ]]; then
      printf 'FALLO control %s: %s errores\n' "$control" "$errors" >&2
      failures=1
    fi
  done < "$controls_file"
  printf 'Controles de integridad evaluados: %s\n' "$checked_controls"
  (( failures == 0 )) || return 1
  ended=$(date +%s)
  printf 'Corrida %s: %ss (escala %s, fecha %s)\n' "$tag" "$((ended-started))" "$SCALE" "$base_date"
}

run_one a "$DATE_A"
run_one b "$DATE_B"

printf '\nResultado por tabla (A vs. B):\n'
diff -u "$TMP_DIR/a.tsv" "$TMP_DIR/b.tsv" > "$TMP_DIR/diff" || true
while IFS=$'\t' read -r table rows hash; do
  other="$(awk -F '\t' -v table="$table" '$1 == table { print $2 "\t" $3 }' "$TMP_DIR/b.tsv")"
  if [[ "$rows"$'\t'"$hash" == "$other" ]]; then printf 'PASS\t%s\t%s\t%s\n' "$table" "$rows" "$hash"; else printf 'FAIL\t%s\t%s\t%s\t%s\n' "$table" "$rows" "$hash" "$other"; fi
done < "$TMP_DIR/a.tsv"
if [[ -s "$TMP_DIR/diff" ]]; then
  printf '\nFAIL: los resultados de las corridas difieren.\n'
  exit 1
fi
printf '\nPASS: todas las tablas públicas coinciden; controles 2–6 sin errores.\n'
