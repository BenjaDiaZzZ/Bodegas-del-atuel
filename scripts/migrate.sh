#!/usr/bin/env bash
# =============================================================================
# migrate.sh · TPI «Bodegas del Atuel» · 8.3
#
# Aplica db/migrations/*.sql en orden sobre una base vacía.
#
# Modos:
#   - Nube (sin --db-url): usa CLOUD_DB_* y CLOUD_ADMIN_*. Prepara bda_owner
#     (LOGIN, dueño de la base), reclama public con aiven_extras si hace falta,
#     aplica 001-006 y 008 como bda_owner, y 007 como administrador porque los
#     COMMENT ON ROLE exigen ADMIN OPTION sobre bda_owner, que solo tiene el
#     rol que lo creó. El administrador conserva CONNECT explícito y membresía
#     en bda_owner para poder administrar.
#   - URL (--db-url): aplica todas las migraciones con el usuario de la URL.
#     Sirve para el dry-run local contra una base scratch.
#
# Uso:
#   PGPASSWORD=... ./scripts/migrate.sh --db-url "postgresql://bodegas@localhost:5432/base_prueba"
#   ./scripts/migrate.sh
#
# Requiere en .env para la nube:
#   CLOUD_DB_HOST, CLOUD_DB_PORT, CLOUD_DB_NAME
#   CLOUD_ADMIN_USER (default avnadmin), CLOUD_ADMIN_PASSWORD
#   BDA_OWNER_PASSWORD
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

DB_URL=""

usage() {
  cat <<'EOF'
Uso: scripts/migrate.sh [opciones]

  --db-url URL   Aplica todas las migraciones con la URL indicada (dry-run
                 local o base externa). No usa las variables CLOUD_DB_*.
  -h, --help     Muestra esta ayuda.

Sin --db-url se usa el modo nube: prepara bda_owner, aplica las migraciones
y deja bda_owner como dueño de la base. Requiere CLOUD_DB_* y CLOUD_ADMIN_*.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-url)
      [[ $# -ge 2 ]] || { echo "Falta la URL para --db-url." >&2; usage >&2; exit 1; }
      DB_URL="$2"; shift 2 ;;
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

MIGRATIONS=(db/migrations/*.sql)
if [[ ! -e "${MIGRATIONS[0]}" ]]; then
  echo "ERROR: no se encontraron migraciones en db/migrations/." >&2
  exit 1
fi

run_migrations() {
  local runner="$1"
  local migration
  for migration in "${MIGRATIONS[@]}"; do
    printf '  aplicando %s ... ' "$(basename "$migration")"
    if "$runner" "$migration"; then
      echo "OK"
    else
      echo "FAIL"
      echo "ERROR: falló $(basename "$migration"); la base quedó parcialmente migrada." >&2
      exit 1
    fi
  done
}

if [[ -n "$DB_URL" ]]; then
  echo "== Migraciones: base indicada por --db-url =="
  psql_url() {
    psql "$DB_URL" -v ON_ERROR_STOP=1 -q -o /dev/null -f "$1"
  }
  run_migrations psql_url
else
  : "${CLOUD_DB_HOST:?Falta CLOUD_DB_HOST en .env}"
  : "${CLOUD_DB_PORT:?Falta CLOUD_DB_PORT en .env}"
  : "${CLOUD_DB_NAME:?Falta CLOUD_DB_NAME en .env}"
  : "${CLOUD_ADMIN_USER:?Falta CLOUD_ADMIN_USER en .env}"
  : "${CLOUD_ADMIN_PASSWORD:?Falta CLOUD_ADMIN_PASSWORD en .env}"
  : "${BDA_OWNER_PASSWORD:?Falta BDA_OWNER_PASSWORD en .env}"
  CLOUD_DB_SSLMODE="${CLOUD_DB_SSLMODE:-require}"

  admin_psql() {
    PGPASSWORD="$CLOUD_ADMIN_PASSWORD" PGSSLMODE="$CLOUD_DB_SSLMODE" \
      psql -h "$CLOUD_DB_HOST" -p "$CLOUD_DB_PORT" -U "$CLOUD_ADMIN_USER" -d "$CLOUD_DB_NAME" "$@"
  }
  owner_psql() {
    PGPASSWORD="$BDA_OWNER_PASSWORD" PGSSLMODE="$CLOUD_DB_SSLMODE" \
      psql -h "$CLOUD_DB_HOST" -p "$CLOUD_DB_PORT" -U bda_owner -d "$CLOUD_DB_NAME" "$@"
  }
  apply_owner() {
    owner_psql -v ON_ERROR_STOP=1 -q -o /dev/null -f "$1"
  }
  apply_admin() {
    admin_psql -v ON_ERROR_STOP=1 -q -o /dev/null -f "$1"
  }

  echo "== Migraciones: bda_owner@${CLOUD_DB_HOST}:${CLOUD_DB_PORT}/${CLOUD_DB_NAME} (sslmode=${CLOUD_DB_SSLMODE}) =="

  cleanup_bootstrap() {
    admin_psql -q -o /dev/null -v ON_ERROR_STOP=0 <<'SQL' >/dev/null 2>&1 || true
ALTER ROLE bda_owner NOCREATEROLE;
SQL
  }
  trap cleanup_bootstrap EXIT

  echo "== Preparando bda_owner y propiedad de la base =="
  admin_psql \
    -v ON_ERROR_STOP=1 \
    -v owner_password="$BDA_OWNER_PASSWORD" \
    -v admin_user="$CLOUD_ADMIN_USER" \
    -q -o /dev/null <<'SQL'
SELECT 'CREATE ROLE bda_owner'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bda_owner')
\gexec
ALTER ROLE bda_owner WITH LOGIN PASSWORD :'owner_password';
ALTER ROLE bda_owner CREATEROLE;
GRANT bda_owner TO :"admin_user";
DO $$
BEGIN
    IF (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = current_database()) <> 'bda_owner' THEN
        EXECUTE format('ALTER DATABASE %I OWNER TO bda_owner', current_database());
    END IF;
END
$$;
SQL

  owner_psql \
    -v ON_ERROR_STOP=1 \
    -v dbname="$CLOUD_DB_NAME" \
    -v admin_user="$CLOUD_ADMIN_USER" \
    -q -o /dev/null <<'SQL'
GRANT CONNECT ON DATABASE :"dbname" TO :"admin_user";
SQL

  PUBLIC_OWNER="$(admin_psql -At -v ON_ERROR_STOP=1 \
    -c "SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'public';")"

  if [[ "$PUBLIC_OWNER" != "pg_database_owner" \
        && "$PUBLIC_OWNER" != "bda_owner" \
        && "$PUBLIC_OWNER" != "$CLOUD_ADMIN_USER" ]]; then
    if admin_psql -At -v ON_ERROR_STOP=1 \
         -c "SELECT 1 FROM pg_available_extensions WHERE name = 'aiven_extras';" \
         | grep -x "1" > /dev/null; then
      echo "== Aiven: reclamando propiedad del esquema public =="
      admin_psql -v ON_ERROR_STOP=1 -q -o /dev/null <<'SQL'
CREATE EXTENSION IF NOT EXISTS aiven_extras CASCADE;
SELECT * FROM aiven_extras.claim_public_schema_ownership();
SQL
    else
      echo "ERROR: el esquema public pertenece a '$PUBLIC_OWNER' y aiven_extras no está disponible." >&2
      echo "  No se puede otorgar CREATE a bda_owner sin reclamar public." >&2
      exit 1
    fi
  fi

  echo "== Habilitando CREATE en public para bda_owner =="
  if ! admin_psql -v ON_ERROR_STOP=1 -q -o /dev/null \
       -c "GRANT USAGE, CREATE ON SCHEMA public TO bda_owner;"; then
    echo "ERROR: no se pudo otorgar CREATE sobre public a bda_owner." >&2
    echo "  En Aiven, ejecutá como avnadmin:" >&2
    echo "    CREATE EXTENSION IF NOT EXISTS aiven_extras CASCADE;" >&2
    echo "    SELECT * FROM aiven_extras.claim_public_schema_ownership();" >&2
    exit 1
  fi

  SCHEMA_EXISTS="$(owner_psql -At -v ON_ERROR_STOP=1 \
    -c "SELECT to_regclass('public.localidad') IS NOT NULL;")"
  if [[ "$SCHEMA_EXISTS" == "t" ]]; then
    echo "ERROR: el esquema ya existe en la base destino." >&2
    echo "  Las migraciones no son idempotentes: recreá la base destino." >&2
    exit 1
  fi

  for migration in "${MIGRATIONS[@]}"; do
    printf '  aplicando %s ... ' "$(basename "$migration")"
    if [[ "$(basename "$migration")" == "007_roles.sql" ]]; then
      runner=apply_admin
    else
      runner=apply_owner
    fi
    if "$runner" "$migration"; then
      echo "OK"
    else
      echo "FAIL"
      echo "ERROR: falló $(basename "$migration"); la base quedó parcialmente migrada." >&2
      exit 1
    fi
  done
fi

SUMMARY_SQL="$(cat <<'SQL'
SELECT 'tablas', count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
UNION ALL
SELECT 'vistas', count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'v'
UNION ALL
SELECT 'secuencias', count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'S'
UNION ALL
SELECT 'rutinas', count(*)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
UNION ALL
SELECT 'triggers', count(DISTINCT tgname)
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND NOT t.tgisinternal
ORDER BY 1;
SQL
)"

echo "== Resumen =="
if [[ -n "$DB_URL" ]]; then
  psql "$DB_URL" -At -F '|' -v ON_ERROR_STOP=1 -c "$SUMMARY_SQL"
else
  owner_psql -At -F '|' -v ON_ERROR_STOP=1 -c "$SUMMARY_SQL"
fi

echo "== Migraciones aplicadas =="
