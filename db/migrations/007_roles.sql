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
--   - app_rw recibe solo el DML permitido, uso de secuencias y EXECUTE sobre
--     funciones/procedimientos. No puede crear objetos.
--   - reporte_ro recibe solo SELECT. No puede ejecutar rutinas ni usar secuencias.
--   - Las contraseñas NO se escriben en este archivo. Los roles se crean sin
--     LOGIN y `scripts/set_role_passwords.sh` les asigna la contraseña desde
--     DB_PASSWORD y REPORTE_RO_PASSWORD. Nunca se commitea .env.
--
-- HALLAZGO R-001 · matriz de privilegios de app_rw (seccion 5b):
--   La API ya no recibe DML de tabla completa sobre las tablas criticas; solo
--   puede insertar las columnas que le corresponden y disparar las rutinas
--   DEFINER (T1, T2, T7 y los procedures de 004), que escriben totales, stocks
--   y auditoria con los permisos del owner. Matriz exacta:
--     comprobante            SELECT; INSERT (fecha, id_cliente, id_sala)
--     renglon_comprobante    SELECT; INSERT (nro_comprobante, cod_vino, cantidad)
--     stock_sala             SELECT
--     stock_deposito         SELECT
--     ingreso                SELECT; INSERT (fecha, id_transportista, cuit_bodega);
--                            UPDATE (estado)
--     transferencia          SELECT; INSERT (id_sala); UPDATE (estado)
--     renglon_ingreso        SELECT; INSERT (cod_ingreso, cod_vino, cantidad);
--                            UPDATE (cantidad); DELETE
--     renglon_transferencia  SELECT; INSERT (nro_solicitud, cod_vino, cantidad);
--                            UPDATE (cantidad); DELETE
--     auditoria_precio       SELECT
--     vino                   sin cambios (DML completo de la seccion 5)
--   Ninguna tabla critica conserva UPDATE ni DELETE de tabla completa.
--
--   ADVERTENCIA: `ALTER DEFAULT PRIVILEGES` (seccion 7) sigue otorgando DML
--   amplio sobre las tablas que se creen en el futuro. Toda tabla sensible
--   nueva debe restrangerse explicitamente con un REVOKE + GRANT por columna
--   como los de la seccion 5b; el default no la protege.
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
-- 5b. Matriz de privilegios de app_rw (hallazgo R-001)
--     La seccion 5 dio DML de tabla completa a app_rw. Con triggers INVOKER
--     eso permitia saltarse los triggers ante una inyeccion SQL y modificar
--     totales, stocks o auditoria a mano. Ahora T1, T2, T7 y los procedures
--     son SECURITY DEFINER (004/005) y app_rw solo conserva lo minimo. El
--     orden importa: primero REVOKE del DML de tabla completa y despues GRANT
--     por columna.
--     Las columnas calculadas por trigger se omiten del GRANT de INSERT: el
--     trigger las completa en NEW sin chequeo de privilegio de columna. Los
--     DEFAULT y las columnas IDENTITY siguen funcionando con GRANT por columna.
-- -----------------------------------------------------------------------------

-- comprobante: la API solo crea la cabecera; los importes los escribe T2.
REVOKE ALL PRIVILEGES ON TABLE comprobante FROM app_rw;
GRANT SELECT ON TABLE comprobante TO app_rw;
GRANT INSERT (fecha, id_cliente, id_sala) ON TABLE comprobante TO app_rw;

-- renglon_comprobante: la API solo envia vino y cantidad; T1 completa importes.
REVOKE ALL PRIVILEGES ON TABLE renglon_comprobante FROM app_rw;
GRANT SELECT ON TABLE renglon_comprobante TO app_rw;
GRANT INSERT (nro_comprobante, cod_vino, cantidad)
    ON TABLE renglon_comprobante TO app_rw;

-- stock_sala / stock_deposito: solo lectura. Toda escritura pasa por T2 o por
-- los procedures DEFINER.
REVOKE ALL PRIVILEGES ON TABLE stock_sala FROM app_rw;
GRANT SELECT ON TABLE stock_sala TO app_rw;
REVOKE ALL PRIVILEGES ON TABLE stock_deposito FROM app_rw;
GRANT SELECT ON TABLE stock_deposito TO app_rw;

-- ingreso: alta sin estado (DEFAULT en_confeccion) y avance de estado.
REVOKE ALL PRIVILEGES ON TABLE ingreso FROM app_rw;
GRANT SELECT ON TABLE ingreso TO app_rw;
GRANT INSERT (fecha, id_transportista, cuit_bodega) ON TABLE ingreso TO app_rw;
GRANT UPDATE (estado) ON TABLE ingreso TO app_rw;

-- transferencia: alta sin fecha ni estado (los fuerza/default el esquema) y
-- avance de estado.
REVOKE ALL PRIVILEGES ON TABLE transferencia FROM app_rw;
GRANT SELECT ON TABLE transferencia TO app_rw;
GRANT INSERT (id_sala) ON TABLE transferencia TO app_rw;
GRANT UPDATE (estado) ON TABLE transferencia TO app_rw;

-- renglones de documento: editables mientras el documento esta en_confeccion
-- (T6 lo valida); la API puede corregir cantidades y borrar renglones.
REVOKE ALL PRIVILEGES ON TABLE renglon_ingreso FROM app_rw;
GRANT SELECT ON TABLE renglon_ingreso TO app_rw;
GRANT INSERT (cod_ingreso, cod_vino, cantidad)
    ON TABLE renglon_ingreso TO app_rw;
GRANT UPDATE (cantidad) ON TABLE renglon_ingreso TO app_rw;
GRANT DELETE ON TABLE renglon_ingreso TO app_rw;

REVOKE ALL PRIVILEGES ON TABLE renglon_transferencia FROM app_rw;
GRANT SELECT ON TABLE renglon_transferencia TO app_rw;
GRANT INSERT (nro_solicitud, cod_vino, cantidad)
    ON TABLE renglon_transferencia TO app_rw;
GRANT UPDATE (cantidad) ON TABLE renglon_transferencia TO app_rw;
GRANT DELETE ON TABLE renglon_transferencia TO app_rw;

-- auditoria_precio: solo lectura; la escribe T7 (DEFINER).
REVOKE ALL PRIVILEGES ON TABLE auditoria_precio FROM app_rw;
GRANT SELECT ON TABLE auditoria_precio TO app_rw;

-- vino: sin cambios a proposito. El precio lo edita la API (queda auditado por
-- T7) y el DML completo de la seccion 5 sigue vigente.

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
--    ADVERTENCIA (R-001): este default da a app_rw DML amplio sobre toda tabla
--    nueva, incluidas las sensibles. Toda tabla sensible que se agregue debe
--    restrangerse explicitamente con REVOKE + GRANT por columna, como en 5b.
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
