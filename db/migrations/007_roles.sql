-- =============================================================================
-- 007_roles.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Rol P3 · Roles y privilegios mínimos.
--
-- Requisito de la etapa 2: 3 roles.
--   bda_owner → propietario lógico de la base y de los objetos.
--   app_rw    → lectura/escritura para la API REST (nunca DDL).
--   reporte_ro → solo lectura para reportes.
--
-- Decisiones de seguridad:
--   - Se revocan los privilegios de PUBLIC sobre el esquema y los objetos.
--   - app_rw recibe solo DML (SELECT/INSERT/UPDATE/DELETE), uso de secuencias
--     y EXECUTE sobre funciones/procedimientos. No puede crear objetos.
--   - reporte_ro recibe solo SELECT. No puede ejecutar rutinas ni usar secuencias.
--   - Las contraseñas NO se escriben en este archivo. Los roles se crean sin
--     LOGIN y `scripts/set_role_passwords.sh` les asigna la contraseña desde
--     DB_PASSWORD y REPORTE_RO_PASSWORD. Nunca se commitea .env.
--
-- En el Docker Compose local, el usuario `POSTGRES_USER` (por defecto
-- `bodegas`) es el propietario real del clúster/base. `bda_owner` queda como
-- rol lógico de propietario para la nube; si se desea transferir la propiedad
-- de los objetos, hacerlo explícitamente con ALTER ... OWNER TO bda_owner.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Creación idempotente de roles
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bda_owner') THEN
        CREATE ROLE bda_owner NOLOGIN;
    END IF;

    -- Compatibilidad con bases creadas antes del rename app_ro → reporte_ro.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_ro')
       AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'reporte_ro') THEN
        EXECUTE 'ALTER ROLE app_ro RENAME TO reporte_ro';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_rw') THEN
        CREATE ROLE app_rw NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'reporte_ro') THEN
        CREATE ROLE reporte_ro NOLOGIN;
    END IF;
END
$$;

-- Las contraseñas se asignan después de la inicialización:
--   ./scripts/set_role_passwords.sh
-- El script lee DB_PASSWORD y REPORTE_RO_PASSWORD del entorno.

COMMENT ON ROLE bda_owner IS
    'Propietario lógico de la base y de los objetos del TPI Bodegas del Atuel.';
COMMENT ON ROLE app_rw IS
    'Rol de lectura/escritura usado por la API REST. Sin permisos DDL.';
COMMENT ON ROLE reporte_ro IS
    'Rol de solo lectura usado por los reportes. Sin permisos de escritura.';

-- -----------------------------------------------------------------------------
-- 2. Cerrar el esquema público
--    En PostgreSQL, PUBLIC tiene USAGE sobre public por defecto. Se revoca
--    para que solo los tres roles del proyecto puedan entrar al esquema.
-- -----------------------------------------------------------------------------
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO bda_owner, app_rw, reporte_ro;
GRANT CREATE ON SCHEMA public TO bda_owner;

-- -----------------------------------------------------------------------------
-- 3. Revocar privilegios heredados por PUBLIC
--    Las funciones reciben EXECUTE para PUBLIC por defecto; se revoca tanto
--    para los objetos actuales como para los futuros.
-- -----------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES  IN SCHEMA public FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 4. Propietario lógico: control total de los objetos existentes
-- -----------------------------------------------------------------------------
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO bda_owner;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO bda_owner;
GRANT ALL PRIVILEGES ON ALL ROUTINES  IN SCHEMA public TO bda_owner;

-- -----------------------------------------------------------------------------
-- 5. API: lectura/escritura sin DDL
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA public
    TO app_rw;

GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA public
    TO app_rw;

GRANT EXECUTE
    ON ALL ROUTINES IN SCHEMA public
    TO app_rw;

-- -----------------------------------------------------------------------------
-- 6. Reportes: solo lectura
--    Se incluyen vistas y tablas. Las vistas permiten encapsular reportes;
--    las tablas quedan disponibles para consultas de solo lectura puntuales.
-- -----------------------------------------------------------------------------
GRANT SELECT
    ON ALL TABLES IN SCHEMA public
    TO reporte_ro;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON ALL TABLES IN SCHEMA public
    FROM reporte_ro;

-- -----------------------------------------------------------------------------
-- 7. Privilegios por defecto para objetos que se creen en el futuro
--    (por ejemplo, índices o vistas de la etapa 4). Se aplican a los objetos
--    creados por el rol que ejecuta esta migración.
-- -----------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON ROUTINES TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO reporte_ro;

-- -----------------------------------------------------------------------------
-- 8. Conexión a la base: quitar CONNECT a PUBLIC y darlo solo a los roles
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO bda_owner, app_rw, reporte_ro',
        current_database()
    );
END
$$;

COMMIT;
