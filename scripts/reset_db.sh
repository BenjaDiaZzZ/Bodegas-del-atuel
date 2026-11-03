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

echo "Eliminando contenedores y volumen de datos..."
docker compose down -v --remove-orphans

echo "Levantando PostgreSQL..."
docker compose up -d db

echo "Esperando a que terminen los scripts de inicialización..."
for _ in $(seq 1 60); do
  if docker compose logs db 2>&1 | grep -q "PostgreSQL init process complete"; then
    break
  fi
  if ! docker compose ps --status running --services | grep -qx "db"; then
    echo "ERROR: el contenedor de PostgreSQL no está corriendo." >&2
    docker compose logs db >&2
    exit 1
  fi
  sleep 1
done

if ! docker compose logs db 2>&1 | grep -q "PostgreSQL init process complete"; then
  echo "ERROR: timeout esperando la inicialización de PostgreSQL." >&2
  docker compose logs db >&2
  exit 1
fi

echo "Esperando el healthcheck..."
for _ in $(seq 1 30); do
  status="$(docker inspect --format '{{.State.Health.Status}}' bodegas_del_atuel_db 2>/dev/null || echo starting)"
  if [[ "$status" == "healthy" ]]; then
    break
  fi
  sleep 1
done

status="$(docker inspect --format '{{.State.Health.Status}}' bodegas_del_atuel_db 2>/dev/null || echo unknown)"
if [[ "$status" != "healthy" ]]; then
  echo "ERROR: PostgreSQL no llegó a estado healthy (estado actual: $status)." >&2
  docker compose logs db >&2
  exit 1
fi

echo "Base recreada. Migraciones disponibles en /docker-entrypoint-initdb.d:"
docker compose exec -T db sh -c 'ls -1 /docker-entrypoint-initdb.d 2>/dev/null || true'

echo "Versión del motor:"
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT version();"
