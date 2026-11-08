-- =============================================================================
-- 007_roles.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Rol P3 · Roles y privilegios mínimos.
--
-- Requisito de la etapa 2: 3 roles.
--   bda_owner  → propietario lógico de la base y de los objetos.
--   app_rw     → lectura/escritura mínima para la API REST (nunca DDL).
--   reporte_ro → solo lectura para reportes.
--
-- PRINCIPIO DE ESTA VERSIÓN: ninguna concesión ni revocación aplica a
-- grupos de objetos. Toda sentencia enumera los objetos de forma explícita y
-- cada bloque indica el requisito que lo justifica (operación OpenAPI,
-- trigger de 005 o procedimiento de 004). Así el análisis de superficie es
-- auditable línea por línea y el requisito P1 (sin UPDATE ni DELETE de
-- renglon_comprobante para app_rw) es verificable.
--
-- Verificación automatizada: db/tests/test_007_roles.sql (matriz en ambos
-- sentidos, denegaciones vivas 42501, fugas por PUBLIC y humo de la cadena
-- SECURITY INVOKER como app_rw).
--
-- RESULTADO EMPÍRICO (PostgreSQL 16.15, probado por P3):
--   SELECT ... FOR UPDATE exige privilegio UPDATE en PostgreSQL 16: con un
--   rol SELECT-only la sentencia falla con SQLSTATE 42501 (permission
--   denied) tanto con filas que bloquear como sobre una tabla vacía (el
--   privilegio se valida al iniciar la ejecución, no por fila; verificado
--   por P3 sobre renglon_transferencia y stock_sala). Por eso el
--   procedimiento sp_procesar_transferencia (004, bloqueo de renglones con
--   FOR UPDATE) justifica UPDATE —nunca DELETE— sobre renglon_ingreso y
--   renglon_transferencia.
--
-- OBSERVACIÓN EMPÍRICA SOBRE FUNCIONES TRIGGER: las 8 funciones trigger de
-- 005 se disparan correctamente con app_rw sin tener EXECUTE concedido sobre
-- ellas (la ejecución del trigger no exige el privilegio del rol disparador).
-- EXECUTE solo se concede a las rutinas que el código de la API llama
-- directamente. Verificado en la sección F de test_007_roles.sql.
--
-- Decisiones de seguridad:
--   - Se revocan los privilegios de PUBLIC sobre el esquema y sobre cada
--     objeto por nombre.
--   - app_rw recibe solo el DML de la matriz de abajo, USAGE en las 6
--     secuencias que usa y EXECUTE en las 6 rutinas contratadas. No puede
--     crear objetos. Ni UPDATE ni DELETE sobre renglon_comprobante.
--   - reporte_ro recibe solo SELECT sobre tablas y vistas. No ejecuta rutinas
--     ni usa secuencias.
--   - No hay privilegios por defecto de escritura: toda tabla futura
--     escribible exige su GRANT explícito aquí (solo SELECT queda por
--     defecto para reporte_ro).
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
    'Rol de lectura/escritura con DML mínimo de la matriz de 007, usado por la API REST. Sin UPDATE ni DELETE de renglon_comprobante. Sin permisos DDL.';
COMMENT ON ROLE reporte_ro IS
    'Rol de solo lectura usado por los reportes. Sin permisos de escritura ni EXECUTE.';

-- -----------------------------------------------------------------------------
-- 2. Cerrar el esquema público
--    En PostgreSQL, PUBLIC tiene USAGE sobre public por defecto. Se revoca
--    para que solo los tres roles del proyecto puedan entrar al esquema.
-- -----------------------------------------------------------------------------
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO bda_owner, app_rw, reporte_ro;
GRANT CREATE ON SCHEMA public TO bda_owner;

-- -----------------------------------------------------------------------------
-- 3. Matriz de privilegios de app_rw y su origen
--    (derivada de: operaciones de escritura de api/openapi.yaml, DML de los
--    triggers de 005 y DML de los procedimientos de 004)
--
--   Tabla                    INS UPD DEL · Justificación
--   ------------------------ --- --- --- + --------------------------------
--   vino                      SÍ SÍ SÍ · crearVino/actualizarVino/eliminarVino; T7 audita el precio; DELETE cascada a composición y maridajes
--   cliente                   SÍ SÍ SÍ · crearCliente/actualizarCliente/eliminarCliente; baja en cascada de subtipos
--   composicion               SÍ – SÍ · crearVino y PUT /vinos/{cod} reemplaza la composición (DELETE+INSERT); T8 valida RN-05
--   vino_maridaje             SÍ – SÍ · idem, reemplazo de maridajes
--   socio                     SÍ – – · crearCliente (tipo socio); baja solo por cascada desde cliente
--   distribuidor              SÍ SÍ – · crearCliente y PUT (zona_cobertura, nro_habilitacion)
--   exportador                SÍ SÍ – · crearCliente y PUT (pais_destino_principal)
--   permiso_exportacion       SÍ – SÍ · alta en crearCliente y reemplazo en PUT /clientes (DELETE+INSERT)
--   comprobante               SÍ SÍ – · crearComprobante; T2 recalcula subtotal/descuento/total
--   renglon_comprobante       SÍ – – · crearComprobante envía (cod_vino, cantidad); T1 completa la línea y T2 descuenta stock. SIN UPDATE NI DELETE (requisito P1: el documento es inmutable y T2 mantiene el total)
--   ingreso                   SÍ SÍ – · crearIngreso, terminarIngreso; FOR UPDATE de cabecera en sp_procesar_ingreso
--   renglon_ingreso           SÍ SÍ – · agregarRenglonIngreso; UPDATE solo por la Regla FOR UPDATE (resultado empírico de arriba)
--   transferencia             SÍ SÍ – · crearTransferencia, terminarTransferencia; FOR UPDATE de cabecera en sp_procesar_transferencia
--   renglon_transferencia     SÍ SÍ – · agregarRenglonTransferencia; UPDATE solo por el FOR UPDATE de renglones en sp_procesar_transferencia
--   stock_deposito            SÍ SÍ – · upsert en sp_procesar_ingreso; descuento en sp_procesar_transferencia
--   stock_sala                SÍ SÍ – · T2 descuenta stock; FOR UPDATE de T1 valida RN-09; upsert en sp_procesar_transferencia
--   auditoria_precio          SÍ – – · T7 (AFTER UPDATE de vino) registra RN-13 con privilegios de app_rw
--   Localidad, cepa, bodega, transportista, maridaje, finca, sala,
--   empleado, parcela, lote_uva, transportista_localidad, analisis_calidad
--                             –   –   – · solo consultas/catálogos para la API (SELECT)
--
--   DELETE de composición/vino_maridaje/permiso_exportacion es necesario
--   porque el reemplazo de colecciones del PUT es DELETE+INSERT directo de
--   la API. Los borradores en cascada (vino, cliente hijos) corren con los
--   privilegios del propietario y no exigen permisos del llamador.
--
--   Secuencias USAGE: vino_cod_vino_seq, cliente_id_cliente_seq,
--   comprobante_nro_comprobante_seq, ingreso_cod_ingreso_seq,
--   transferencia_nro_solicitud_seq, auditoria_precio_id_auditoria_seq
--   (inserta app_rw por sí o por trigger T7).
--
--   Rutinas EXECUTE: fn_descuento_cliente, fn_total_comprobante,
--   fn_stock_sala, fn_antiguedad_anios, sp_procesar_ingreso,
--   sp_procesar_transferencia.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 4. Revocar a PUBLIC todo privilegio por defecto, objeto por objeto
--    Las tablas y vistas nacen sin ACL (solo PUBLIC no recibe nada dentro de
--    los defaults), pero el REVOKE explícito fija una ACL vacía por objeto:
--    así ninguna concesión quedará oculta por un default y el estado queda
--    asertable (test_007_roles.sql, sección D).
-- -----------------------------------------------------------------------------
-- Operando/catálogo, entidades y movimientos (las 29 tablas).
REVOKE ALL PRIVILEGES ON TABLE localidad, cepa, bodega, transportista,
    maridaje, finca, sala, empleado, parcela, vino, cliente, lote_uva,
    composicion, vino_maridaje, socio, distribuidor, exportador,
    permiso_exportacion, transportista_localidad, analisis_calidad,
    auditoria_precio, comprobante, renglon_comprobante, ingreso,
    renglon_ingreso, transferencia, renglon_transferencia, stock_deposito,
    stock_sala
    FROM PUBLIC;

-- Las 4 vistas de reportes y fichas.
REVOKE ALL PRIVILEGES ON TABLE vw_stock_total_vino, vw_ventas_mensuales_sala,
    vw_documentos_pendientes, vw_ficha_vino
    FROM PUBLIC;

-- Las 13 secuencias de las tablas con PK identity.
REVOKE ALL PRIVILEGES ON SEQUENCE localidad_id_localidad_seq, cepa_id_cepa_seq,
    transportista_id_transportista_seq, maridaje_id_maridaje_seq,
    finca_id_finca_seq, sala_id_sala_seq, cliente_id_cliente_seq,
    analisis_calidad_id_analisis_seq, auditoria_precio_id_auditoria_seq,
    comprobante_nro_comprobante_seq, ingreso_cod_ingreso_seq,
    transferencia_nro_solicitud_seq, vino_cod_vino_seq
    FROM PUBLIC;

-- Las 14 rutinas de 003 (negocio), 004 (procedimientos) y 005 (triggers).
-- PUBLIC recibe EXECUTE por defecto en las funciones: aquí se quita.
REVOKE ALL PRIVILEGES ON ROUTINE fn_descuento_cliente(varchar),
    fn_stock_sala(integer, integer), fn_antiguedad_anios(date),
    fn_total_comprobante(integer), sp_procesar_ingreso(integer),
    sp_procesar_transferencia(integer), fn_tg_renglon_venta_completar(),
    fn_tg_renglon_venta_actualizar(), fn_tg_ingreso_estado(),
    fn_tg_transferencia_estado(), fn_tg_transferencia_fecha(),
    fn_tg_renglon_documento_bloqueo(), fn_tg_vino_precio_auditoria(),
    fn_tg_composicion_cien()
    FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 5. Propietario lógico: control total, objeto por objeto
-- -----------------------------------------------------------------------------
-- bda_owner es el fondo de seguridad de la operatoria: si un día la API
-- requiere un acceso distinto de DML, es el rol que restaura o transfiere lo
-- que app_rw no puede tocar.
GRANT ALL PRIVILEGES ON TABLE localidad, cepa, bodega, transportista,
    maridaje, finca, sala, empleado, parcela, vino, cliente, lote_uva,
    composicion, vino_maridaje, socio, distribuidor, exportador,
    permiso_exportacion, transportista_localidad, analisis_calidad,
    auditoria_precio, comprobante, renglon_comprobante, ingreso,
    renglon_ingreso, transferencia, renglon_transferencia, stock_deposito,
    stock_sala
    TO bda_owner;

-- En vistas: control total también (las vistas no son operandos, pero el
-- propietario decide).
GRANT ALL PRIVILEGES ON TABLE vw_stock_total_vino, vw_ventas_mensuales_sala,
    vw_documentos_pendientes, vw_ficha_vino
    TO bda_owner;

GRANT ALL PRIVILEGES ON SEQUENCE localidad_id_localidad_seq, cepa_id_cepa_seq,
    transportista_id_transportista_seq, maridaje_id_maridaje_seq,
    finca_id_finca_seq, sala_id_sala_seq, cliente_id_cliente_seq,
    analisis_calidad_id_analisis_seq, auditoria_precio_id_auditoria_seq,
    comprobante_nro_comprobante_seq, ingreso_cod_ingreso_seq,
    transferencia_nro_solicitud_seq, vino_cod_vino_seq
    TO bda_owner;

GRANT ALL PRIVILEGES ON ROUTINE fn_descuento_cliente(varchar),
    fn_stock_sala(integer, integer), fn_antiguedad_anios(date),
    fn_total_comprobante(integer), sp_procesar_ingreso(integer),
    sp_procesar_transferencia(integer), fn_tg_renglon_venta_completar(),
    fn_tg_renglon_venta_actualizar(), fn_tg_ingreso_estado(),
    fn_tg_transferencia_estado(), fn_tg_transferencia_fecha(),
    fn_tg_renglon_documento_bloqueo(), fn_tg_vino_precio_auditoria(),
    fn_tg_composicion_cien()
    TO bda_owner;

-- -----------------------------------------------------------------------------
-- 6. app_rw: DML mínimo según la matriz de la sección 3
-- -----------------------------------------------------------------------------
-- SELECT: toda la API lee. Tablas (consultas, listados, obtención),
-- operaciones GET y de listado incluidos los reportes internos.
GRANT SELECT ON TABLE localidad, cepa, bodega, transportista, maridaje, finca,
    sala, empleado, parcela, vino, cliente, lote_uva, composicion,
    vino_maridaje, socio, distribuidor, exportador, permiso_exportacion,
    transportista_localidad, analisis_calidad, auditoria_precio, comprobante,
    renglon_comprobante, ingreso, renglon_ingreso, transferencia,
    renglon_transferencia, stock_deposito, stock_sala
    TO app_rw;

-- SELECT en vistas: GET /vinos/{cod} usa vw_ficha_vino y detalles para
-- consultas; reportes puntuales de la API.
GRANT SELECT ON TABLE vw_stock_total_vino, vw_ventas_mensuales_sala,
    vw_documentos_pendientes, vw_ficha_vino
    TO app_rw;

-- INSERT: escrituras contratadas de la API (POST) + auditoria_precio que
-- el trigger T7 inserta con privilegios de app_rw. NO renglon_comprobante
-- UPDATE/DELETE (ver comentario en la sección 3): el renglón es inmutable.
GRANT INSERT ON TABLE vino, cliente, composicion, vino_maridaje, socio,
    distribuidor, exportador, permiso_exportacion, comprobante,
    renglon_comprobante, ingreso, renglon_ingreso, transferencia,
    renglon_transferencia, stock_deposito, stock_sala, auditoria_precio
    TO app_rw;

-- UPDATE: operandos modificables por la API (vino, cliente y los atributos
-- propios de distribuidor y exportador por PUT), cabeceras de documentos
-- (terminar*), stocks y los recálculos de T2. renglon_ingreso y
-- renglon_transferencia reciben UPDATE solo por el bloqueo SELECT ... FOR
-- UPDATE de sp_procesar_* (resultado empírico del encabezado). Ni
-- renglon_comprobante (requisito P1) ni las demás tablas reciben UPDATE.
GRANT UPDATE ON TABLE vino, cliente, comprobante, stock_sala, stock_deposito,
    ingreso, transferencia, renglon_ingreso, renglon_transferencia,
    distribuidor, exportador
    TO app_rw;

-- DELETE: solo bajas directas del contrato: DELETE /vinos y DELETE
-- /clientes, y el reemplazo de colecciones del PUT (composición, maridajes
-- y permisos como DELETE+INSERT). Las demás bajas son cascadas desde vino o
-- cliente y no requieren permisos sobre el hijo.
GRANT DELETE ON TABLE vino, cliente, composicion, vino_maridaje,
    permiso_exportacion
    TO app_rw;

-- USAGE de secuencias: PK identity de las tablas que app_rw inserta por sí
-- (vino, cliente, comprobante, ingreso, transferencia) o por trigger T7
-- (auditoria_precio). Sin USAGE, el INSERT fallaría con 42501. Sin SELECT:
-- no se usa currval en el código de la API.
GRANT USAGE ON SEQUENCE vino_cod_vino_seq, cliente_id_cliente_seq,
    comprobante_nro_comprobante_seq, ingreso_cod_ingreso_seq,
    transferencia_nro_solicitud_seq, auditoria_precio_id_auditoria_seq
    TO app_rw;

-- EXECUTE de las rutinas que la API llama directamente: descuentos y
-- validaciones de consulta (003) y los dos procedimientos operativos (004).
-- Las funciones trigger de 005 NO necesitan EXECUTE del rol disparador
-- (observación empírica del encabezado).
GRANT EXECUTE ON ROUTINE fn_descuento_cliente(varchar),
    fn_stock_sala(integer, integer), fn_antiguedad_anios(date),
    fn_total_comprobante(integer), sp_procesar_ingreso(integer),
    sp_procesar_transferencia(integer)
    TO app_rw;

-- -----------------------------------------------------------------------------
-- 7. reporte_ro: solo lectura, objeto por objeto
-- -----------------------------------------------------------------------------
-- SELECT sobre las 29 tablas: los reportes y las consultas del rol leen
GRANT SELECT ON TABLE localidad, cepa, bodega, transportista, maridaje, finca,
    sala, empleado, parcela, vino, cliente, lote_uva, composicion,
    vino_maridaje, socio, distribuidor, exportador, permiso_exportacion,
    transportista_localidad, analisis_calidad, auditoria_precio, comprobante,
    renglon_comprobante, ingreso, renglon_ingreso, transferencia,
    renglon_transferencia, stock_deposito, stock_sala
    TO reporte_ro;

-- SELECT sobre las 4 vistas de reportes y fichas (GET /reportes/*).
GRANT SELECT ON TABLE vw_stock_total_vino, vw_ventas_mensuales_sala,
    vw_documentos_pendientes, vw_ficha_vino
    TO reporte_ro;

-- -----------------------------------------------------------------------------
-- 8. Privilegios por defecto para objetos futuros
--    (por ejemplo, vistas de reportes o índices de la etapa 4). Se aplican a
--    los objetos creados por el rol que ejecuta esta migración.
--
--    NO hay escrituras implícitas: cualquier tabla futura escribible exige
--    su GRANT explícito en este archivo (o en una migración posterior), con
--    la matriz de la sección 3 como fundamento.
--
--    LÍMITE OBSERVADO (PostgreSQL 16.15): si el resultado de un ALTER
--    DEFAULT PRIVILEGES es una ACL vacía, PostgreSQL la descarta; por eso el
--    REVOKE de EXECUTE de rutinas futuras queda solo como declaración de
--    intención y NO cancela el EXECUTE por defecto de PUBLIC en funciones
--    nuevas. El control efectivo es el REVOKE por objeto de la sección 4 y,
--    para rutinas futuras, el par GRANT/REVOKE explícito en cada migración.
-- -----------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO reporte_ro;

-- -----------------------------------------------------------------------------
-- 9. Conexión a la base: quitar CONNECT a PUBLIC y darlo solo a los roles
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
