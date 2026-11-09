-- =============================================================================
-- test_007_roles.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Pruebas de la matriz de privilegios minimos de 007_roles.sql.
--
-- Ejecución (sobre una base recién inicializada con 001 → 007):
--   psql -v ON_ERROR_STOP=1 -f db/tests/test_007_roles.sql
--
-- Estrategia:
--   * Todo ocurre dentro de BEGIN … ROLLBACK: la prueba no deja residuos
--     (roles, datos y funciones creadas dentro de la transacción se deshacen).
--   * Sección A: matriz de privilegios efectivos en ambos sentidos con
--     has_table_privilege / has_sequence_privilege / has_function_privilege.
--     Cada celda concedida debe ser verdadera; cada celda retenida, falsa.
--   * Sección B: el REQUISITO central de P1 — como app_rw, UPDATE y DELETE
--     sobre renglon_comprobante deben fallar con SQLSTATE 42501
--     (insufficient_privilege). Si alguna sentencia tiene éxito, la prueba
--     falla inmediatamente (el privilegio quedó concedido de más).
--   * Sección C: reporte_ro no puede escribir (representativas: vino,
--     comprobante, stock_sala).
--   * Sección D: sin fugas por PUBLIC — un rol probe recién creado no puede
--     leer nada y ninguna ACL de tablas, vistas, secuencias, rutinas o del
--     esquema concede algo al grantee 0 (PUBLIC).
--   * Sección E: pg_default_acl no define INSERT/UPDATE/DELETE por defecto
--     para app_rw ni escrituras por defecto para reporte_ro; app_rw y
--     reporte_ro no son miembros de ningún otro rol.
--   * Sección F: humo del lado permitido como app_rw (detecta subconcesion).
--     Siembra catálogos como superusuario y ejecuta el camino de la API como
--     app_rw con IDs 91xx: venta (comprobante + renglón), procesado de
--     ingreso y transferencia (CALL sp_procesar_*) y actualización de precio
--     de vino. Comprueba los efectos de los triggers de 005 —que mezcla ambos
--     modos: T3–T6, T8 y T9 son SECURITY INVOKER; T1, T2 y T7 son
--     SECURITY DEFINER— con literales independientes: recalculo de total y
--     descuento de stock, estados y auditoría de precio.
--   * Sección G: columnas fuera de la matriz (totales, stocks, fecha de
--     cabecera, auditoría) fallan con 42501 como app_rw.
--   * Sección H: UPDATE(estado) y UPDATE(cantidad) de la matriz se permiten.
--   * Sección I: app_rw no tiene USAGE de secuencia y la PK identity se
--     genera igual (BY DEFAULT en cliente, ALWAYS en vino).
--   * Sección J: reporte_ro lee las 4 vistas aun con las tablas base
--     revocadas (acceso con permisos del owner de la vista) y no lee una
--     tabla no habilitada.
--   * Sección K: re-aplicar 007 no altera la ACL y CREATE OR REPLACE VIEW de
--     006 conserva los GRANT de las vistas.
--   * No es tautológica: los valores esperados son literales calculados a mano
--     (socio = 10 %: precio 1000, cantidad 2 → total 1800, stock 10 → 8).
--
-- Estado esperado con 001 → 007 aplicadas (versión con GRANT minimos por
-- objeto y sin ON ALL TABLES): todas las aserciones pasan. Contra una 007 que
-- conceda privilegios globales falla con mensajes "FAIL:" explicitos.
--
-- Mensajes de error: identifican rol, objeto, privilegio, valor observado y
-- esperado, sin caracteres especiales (convención de contratos.md).
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Precondición: base recién inicializada con 001 → 007.
--    Sin este chequeo, los IDs 91xx pueden chocar con datos de una base
--    reutilizada y la sección F fallaría con violaciones de UNIQUE confusas.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM localidad      WHERE id_localidad = 9101)
       OR EXISTS (SELECT 1 FROM cepa        WHERE id_cepa = 9101)
       OR EXISTS (SELECT 1 FROM bodega      WHERE cuit = '20000000091')
       OR EXISTS (SELECT 1 FROM transportista WHERE id_transportista = 9101)
       OR EXISTS (SELECT 1 FROM sala        WHERE id_sala = 9101)
       OR EXISTS (SELECT 1 FROM cliente     WHERE nombre LIKE 'Cliente Test 007%')
       OR EXISTS (SELECT 1 FROM vino        WHERE nombre_comercial LIKE 'Vino Test 007%')
       OR EXISTS (SELECT 1 FROM comprobante WHERE nro_comprobante = 9101)
       OR EXISTS (SELECT 1 FROM ingreso     WHERE cod_ingreso = 9101)
       OR EXISTS (SELECT 1 FROM transferencia WHERE nro_solicitud = 9101)
    THEN
        RAISE EXCEPTION 'test_007_roles: la base no esta limpia; ejecutar sobre una base recien inicializada con 001 → 007';
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 0b. Funciones de aserción (viven solo dentro de la transacción).
-- -----------------------------------------------------------------------------

-- Aserción de una celda de la matriz de tablas (también vale para vistas).
CREATE OR REPLACE FUNCTION pg_temp.t7_priv(p_rol text, p_rel text, p_priv text, p_esperado boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_obs boolean;
BEGIN
    SELECT has_table_privilege(p_rol, p_rel, p_priv) INTO v_obs;
    IF v_obs IS DISTINCT FROM p_esperado THEN
        RAISE EXCEPTION 'FAIL: rol % PRIV % en %: esperado %, observado %',
            p_rol, p_priv, p_rel,
            CASE WHEN p_esperado THEN 'concedido' ELSE 'retenido' END,
            CASE WHEN v_obs THEN 'concedido' ELSE 'retenido' END;
    END IF;
END
$$;

-- Aserción de secuencias.
CREATE OR REPLACE FUNCTION pg_temp.t7_seq(p_rol text, p_seq text, p_priv text, p_esperado boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_obs boolean;
BEGIN
    SELECT has_sequence_privilege(p_rol, p_seq, p_priv) INTO v_obs;
    IF v_obs IS DISTINCT FROM p_esperado THEN
        RAISE EXCEPTION 'FAIL: rol % PRIV SEQUENCE % sobre %: esperado %, observado %',
            p_rol, p_priv, p_seq,
            CASE WHEN p_esperado THEN 'concedido' ELSE 'retenido' END,
            CASE WHEN v_obs THEN 'concedido' ELSE 'retenido' END;
    END IF;
END
$$;

-- Aserción de EXECUTE sobre rutinas (funciones SQL/plpgsql y procedimientos).
CREATE OR REPLACE FUNCTION pg_temp.t7_exec(p_rol text, p_rut text, p_esperado boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_obs boolean;
BEGIN
    SELECT has_function_privilege(p_rol, p_rut::regprocedure, 'EXECUTE') INTO v_obs;
    IF v_obs IS DISTINCT FROM p_esperado THEN
        RAISE EXCEPTION 'FAIL: rol % EXECUTE sobre %: esperado %, observado %',
            p_rol, p_rut,
            CASE WHEN p_esperado THEN 'concedido' ELSE 'retenido' END,
            CASE WHEN v_obs THEN 'concedido' ELSE 'retenido' END;
    END IF;
END
$$;

-- Aserción de privilegio por columna (GRANT INSERT/UPDATE (columna)).
CREATE OR REPLACE FUNCTION pg_temp.t7_col(p_rol text, p_rel text, p_col text,
                                          p_priv text, p_esperado boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_obs boolean;
BEGIN
    SELECT has_column_privilege(p_rol, p_rel, p_col, p_priv) INTO v_obs;
    IF v_obs IS DISTINCT FROM p_esperado THEN
        RAISE EXCEPTION 'FAIL: rol % PRIV % en columna %.%: esperado %, observado %',
            p_rol, p_priv, p_rel, p_col,
            CASE WHEN p_esperado THEN 'concedido' ELSE 'retenido' END,
            CASE WHEN v_obs THEN 'concedido' ELSE 'retenido' END;
    END IF;
END
$$;

-- Aserción por dirección: recorre la lista completa de tablas y exige que
-- exactamente las de p_permitidas tengan el privilegio (las demas, no). Esto
-- impide tanto la subconcesión como la subretención.
CREATE OR REPLACE FUNCTION pg_temp.t7_dir(p_rol text, p_priv text, p_permitidas text[], p_todas text[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r text;
BEGIN
    FOREACH r IN ARRAY p_todas LOOP
        PERFORM pg_temp.t7_priv(p_rol, r, p_priv, r = ANY (p_permitidas));
    END LOOP;
END
$$;

-- -----------------------------------------------------------------------------
-- Secciones A a E: matriz efectiva, denegaciones vivas, fugas por PUBLIC,
-- privilegios por defecto y herencia de roles.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    c_todas    text[] := ARRAY[
        'localidad', 'cepa', 'bodega', 'transportista', 'maridaje', 'finca',
        'sala', 'empleado', 'parcela', 'vino', 'cliente', 'lote_uva',
        'composicion', 'vino_maridaje', 'socio', 'distribuidor', 'exportador',
        'permiso_exportacion', 'transportista_localidad', 'analisis_calidad',
        'auditoria_precio', 'comprobante', 'renglon_comprobante', 'ingreso',
        'renglon_ingreso', 'transferencia', 'renglon_transferencia',
        'stock_deposito', 'stock_sala'];

    c_vistas   text[] := ARRAY[
        'vw_stock_total_vino', 'vw_ventas_mensuales_sala',
        'vw_documentos_pendientes', 'vw_ficha_vino'];

    c_seqs     text[] := ARRAY[
        'localidad_id_localidad_seq', 'cepa_id_cepa_seq',
        'transportista_id_transportista_seq', 'maridaje_id_maridaje_seq',
        'finca_id_finca_seq', 'sala_id_sala_seq', 'cliente_id_cliente_seq',
        'analisis_calidad_id_analisis_seq', 'auditoria_precio_id_auditoria_seq',
        'comprobante_nro_comprobante_seq', 'ingreso_cod_ingreso_seq',
        'transferencia_nro_solicitud_seq', 'vino_cod_vino_seq'];

    -- app_rw no recibe USAGE de ninguna secuencia (R-013): la generación de
    -- PK identity no lo exige y la API nunca llama nextval/currval/setval.
    c_seqs_rw  text[] := ARRAY[]::text[];

    c_rtines   text[] := ARRAY[  -- las 15 rutinas de 003, 004 y 005
        'fn_descuento_cliente(varchar)',
        'fn_stock_sala(integer, integer)',
        'fn_antiguedad_anios(date)',
        'fn_total_comprobante(integer)',
        'sp_procesar_ingreso(integer)',
        'sp_procesar_transferencia(integer)',
        'fn_tg_renglon_venta_completar()',
        'fn_tg_renglon_venta_actualizar()',
        'fn_tg_ingreso_estado()',
        'fn_tg_transferencia_estado()',
        'fn_tg_transferencia_fecha()',
        'fn_tg_renglon_documento_bloqueo()',
        'fn_tg_vino_precio_auditoria()',
        'fn_tg_composicion_cien()',
        'fn_tg_renglon_venta_inmutable()'];

    c_rtines_api text[] := ARRAY[  -- rutinas que la API llama a propósito
        'fn_descuento_cliente(varchar)',
        'fn_stock_sala(integer, integer)',
        'fn_antiguedad_anios(date)',
        'fn_total_comprobante(integer)',
        'sp_procesar_ingreso(integer)',
        'sp_procesar_transferencia(integer)'];

    -- app_rw INSERT de TABLA COMPLETA: solo las tablas cuyo contrato
    -- permite escribir cualquier columna. Las tablas críticas reciben
    -- INSERT por columna y se verifican con t7_col más abajo (R-001/R-005).
    c_app_ins text[] := ARRAY[
        'vino', 'cliente', 'composicion', 'vino_maridaje', 'socio',
        'distribuidor', 'exportador', 'permiso_exportacion'];

    -- app_rw UPDATE de TABLA COMPLETA: solo operandos editables por PUT.
    -- Los estados de ingreso/transferencia (UPDATE (estado)) y la cantidad
    -- de los renglones (UPDATE (cantidad), habilitada por T6) son GRANT por
    -- columna y se verifican con t7_col.
    c_app_upd text[] := ARRAY[
        'vino', 'cliente', 'distribuidor', 'exportador'];

    -- app_rw SELECT en tablas base: todo el esquema (consulta y listados).
    -- reporte_ro, en cambio, solo lee las 6 tablas de sus reportes (R-011).
    c_rep_sel text[] := ARRAY[
        'vino', 'renglon_comprobante', 'stock_sala', 'stock_deposito',
        'transportista', 'ingreso'];

    -- app_rw DELETE: solo bajas directas contratadas (PUT /vinos reemplaza
    -- composición y maridajes; PUT /clientes reemplaza permisos; DELETE
    -- /vinos y /clientes). El resto de las bajas ocurre en cascada desde el
    -- padre y no requiere privilegio en el hijo.
    c_app_del text[] := ARRAY[
        'vino', 'cliente', 'composicion', 'vino_maridaje',
        'permiso_exportacion'];

    r text;
BEGIN
    ---------------------------------------------------------------------------
    -- A. Matriz de privilegios efectiva en ambos sentidos.
    ---------------------------------------------------------------------------

    -- SELECT: bda_owner y app_rw en todas las tablas; reporte_ro solo en
    -- las 6 tablas base que respaldan los reportes (R-011).
    PERFORM pg_temp.t7_dir('bda_owner',  'SELECT', c_todas, c_todas);
    PERFORM pg_temp.t7_dir('app_rw',     'SELECT', c_todas, c_todas);
    PERFORM pg_temp.t7_dir('reporte_ro', 'SELECT', c_rep_sel, c_todas);

    -- SELECT en las 4 vistas para app_rw y reporte_ro (los reportes corren
    -- como reporte_ro y las consultas de detalle de la API, como app_rw).
    FOREACH r IN ARRAY c_vistas LOOP
        PERFORM pg_temp.t7_priv('bda_owner',  r, 'SELECT', true);
        PERFORM pg_temp.t7_priv('app_rw',     r, 'SELECT', true);
        PERFORM pg_temp.t7_priv('reporte_ro', r, 'SELECT', true);
    END LOOP;

    -- En vistas no hay escritura para nadie (ni siquiera para app_rw):
    -- las vistas son materializaciones de consultas, no operandos.
    FOREACH r IN ARRAY c_vistas LOOP
        PERFORM pg_temp.t7_priv('app_rw',     r, 'INSERT', false);
        PERFORM pg_temp.t7_priv('app_rw',     r, 'UPDATE', false);
        PERFORM pg_temp.t7_priv('app_rw',     r, 'DELETE', false);
        PERFORM pg_temp.t7_priv('reporte_ro', r, 'INSERT', false);
        PERFORM pg_temp.t7_priv('reporte_ro', r, 'UPDATE', false);
        PERFORM pg_temp.t7_priv('reporte_ro', r, 'DELETE', false);
    END LOOP;

    -- INSERT: bda_owner en todo; app_rw solo en su lista; reporte_ro en nada.
    PERFORM pg_temp.t7_dir('bda_owner',  'INSERT', c_todas, c_todas);
    PERFORM pg_temp.t7_dir('app_rw',     'INSERT', c_app_ins, c_todas);
    PERFORM pg_temp.t7_dir('reporte_ro', 'INSERT', ARRAY[]::text[], c_todas);

    -- UPDATE.
    PERFORM pg_temp.t7_dir('bda_owner',  'UPDATE', c_todas, c_todas);
    PERFORM pg_temp.t7_dir('app_rw',     'UPDATE', c_app_upd, c_todas);
    PERFORM pg_temp.t7_dir('reporte_ro', 'UPDATE', ARRAY[]::text[], c_todas);

    -- DELETE.
    PERFORM pg_temp.t7_dir('bda_owner',  'DELETE', c_todas, c_todas);
    PERFORM pg_temp.t7_dir('app_rw',     'DELETE', c_app_del, c_todas);
    PERFORM pg_temp.t7_dir('reporte_ro', 'DELETE', ARRAY[]::text[], c_todas);

    RAISE NOTICE 'OK (A): matriz efectiva de tablas y vistas correcta (3 roles × 5 privilegios)';

    ---------------------------------------------------------------------------
    -- A. INSERT por columna en las tablas críticas (R-001/R-005): la tabla
    --    NO tiene INSERT de tabla completa y solo las columnas de origen lo
    --    tienen; las columnas derivadas quedan retenidas.
    ---------------------------------------------------------------------------
    PERFORM pg_temp.t7_priv('app_rw', 'comprobante', 'INSERT', false);
    PERFORM pg_temp.t7_col('app_rw', 'comprobante', 'fecha', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'comprobante', 'id_cliente', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'comprobante', 'id_sala', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'comprobante', 'total', 'INSERT', false);
    PERFORM pg_temp.t7_col('app_rw', 'comprobante', 'descuento', 'INSERT', false);

    PERFORM pg_temp.t7_priv('app_rw', 'renglon_comprobante', 'INSERT', false);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_comprobante', 'nro_comprobante', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_comprobante', 'cod_vino', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_comprobante', 'cantidad', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_comprobante', 'precio_unitario', 'INSERT', false);

    PERFORM pg_temp.t7_priv('app_rw', 'ingreso', 'INSERT', false);
    PERFORM pg_temp.t7_col('app_rw', 'ingreso', 'fecha', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'ingreso', 'id_transportista', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'ingreso', 'cuit_bodega', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'ingreso', 'estado', 'INSERT', false);

    PERFORM pg_temp.t7_priv('app_rw', 'transferencia', 'INSERT', false);
    PERFORM pg_temp.t7_col('app_rw', 'transferencia', 'id_sala', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'transferencia', 'fecha_confeccion', 'INSERT', false);

    PERFORM pg_temp.t7_priv('app_rw', 'renglon_ingreso', 'INSERT', false);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_ingreso', 'cod_ingreso', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_ingreso', 'cod_vino', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_ingreso', 'cantidad', 'INSERT', true);

    PERFORM pg_temp.t7_priv('app_rw', 'renglon_transferencia', 'INSERT', false);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_transferencia', 'nro_solicitud', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_transferencia', 'cod_vino', 'INSERT', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_transferencia', 'cantidad', 'INSERT', true);

    RAISE NOTICE 'OK (A): INSERT por columna correcto en las 6 tablas críticas';

    ---------------------------------------------------------------------------
    -- A. UPDATE por columna (R-012): estados de cabecera y cantidad de los
    --    renglones; el resto de las columnas, y los stocks/totales, quedan
    --    retenidos (los escriben T1/T2/T7 y sp_procesar_*, DEFINER).
    ---------------------------------------------------------------------------
    PERFORM pg_temp.t7_priv('app_rw', 'ingreso', 'UPDATE', false);
    PERFORM pg_temp.t7_col('app_rw', 'ingreso', 'estado', 'UPDATE', true);
    PERFORM pg_temp.t7_col('app_rw', 'ingreso', 'fecha', 'UPDATE', false);
    PERFORM pg_temp.t7_col('app_rw', 'ingreso', 'cuit_bodega', 'UPDATE', false);

    PERFORM pg_temp.t7_priv('app_rw', 'transferencia', 'UPDATE', false);
    PERFORM pg_temp.t7_col('app_rw', 'transferencia', 'estado', 'UPDATE', true);
    PERFORM pg_temp.t7_col('app_rw', 'transferencia', 'fecha_confeccion', 'UPDATE', false);

    PERFORM pg_temp.t7_priv('app_rw', 'renglon_ingreso', 'UPDATE', false);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_ingreso', 'cantidad', 'UPDATE', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_ingreso', 'cod_vino', 'UPDATE', false);

    PERFORM pg_temp.t7_priv('app_rw', 'renglon_transferencia', 'UPDATE', false);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_transferencia', 'cantidad', 'UPDATE', true);
    PERFORM pg_temp.t7_col('app_rw', 'renglon_transferencia', 'nro_solicitud', 'UPDATE', false);

    PERFORM pg_temp.t7_col('app_rw', 'comprobante', 'total', 'UPDATE', false);
    PERFORM pg_temp.t7_col('app_rw', 'stock_sala', 'cantidad', 'UPDATE', false);
    PERFORM pg_temp.t7_col('app_rw', 'stock_deposito', 'cantidad', 'UPDATE', false);

    RAISE NOTICE 'OK (A): UPDATE por columna correcto (estado/cantidad) y retenido en stocks y totales';

    ---------------------------------------------------------------------------
    -- A. Secuencias: bda_owner total; app_rw NO tiene USAGE en ninguna
    --    (R-013: la PK identity se genera sin privilegio de secuencia y la
    --    API nunca llama nextval); reporte_ro ninguna.
    ---------------------------------------------------------------------------
    FOREACH r IN ARRAY c_seqs LOOP
        PERFORM pg_temp.t7_seq('bda_owner',  r, 'USAGE', true);
        PERFORM pg_temp.t7_seq('app_rw',     r, 'USAGE', r = ANY (c_seqs_rw));
        PERFORM pg_temp.t7_seq('reporte_ro', r, 'USAGE', false);
    END LOOP;
    RAISE NOTICE 'OK (A): matriz de secuencias correcta (13 × 3 roles, USAGE)';

    ---------------------------------------------------------------------------
    -- A. Rutinas: bda_owner EXECUTE en las 15; app_rw solo en las 6 que la
    --    API llama (las funciones trigger se disparan sin EXECUTE del rol
    --    disparador; se verifica funcionalmente en la sección F).
    --    reporte_ro no ejecuta rutinas: consulta tablas y vistas.
    ---------------------------------------------------------------------------
    FOREACH r IN ARRAY c_rtines LOOP
        PERFORM pg_temp.t7_exec('bda_owner',  r, true);
        PERFORM pg_temp.t7_exec('app_rw',     r, r = ANY (c_rtines_api));
        PERFORM pg_temp.t7_exec('reporte_ro', r, false);
    END LOOP;
    RAISE NOTICE 'OK (A): matriz de rutinas correcta (15 × 3 roles, EXECUTE)';

    -- T9 (PR #14) debe estar cubierta por los REVOKE/GRANT por rutina:
    -- sin EXECUTE para app_rw ni para PUBLIC, con EXECUTE para bda_owner.
    PERFORM pg_temp.t7_exec('app_rw',    'fn_tg_renglon_venta_inmutable()', false);
    PERFORM pg_temp.t7_exec('bda_owner', 'fn_tg_renglon_venta_inmutable()', true);
    RAISE NOTICE 'OK (A): T9 fn_tg_renglon_venta_inmutable sin EXECUTE para app_rw y con EXECUTE para bda_owner';

    ---------------------------------------------------------------------------
    -- B. REQUISITO de P1: como app_rw, UPDATE y DELETE sobre
    --    renglon_comprobante deben rechazarse con SQLSTATE 42501.
    --    La comprobación de privilegio de UPDATE/DELETE ocurre al
    --    inicializar el plan, no al leer filas: WHERE FALSO basta.
    ---------------------------------------------------------------------------
    PERFORM set_config('role', 'app_rw', true);

    BEGIN
        UPDATE renglon_comprobante
           SET cantidad = cantidad
         WHERE nro_comprobante < 0;
        RAISE EXCEPTION 'FAIL: app_rw hizo UPDATE sobre renglon_comprobante sin recibir error';
    EXCEPTION WHEN others THEN
        IF SQLSTATE IS DISTINCT FROM '42501' THEN
            RAISE EXCEPTION 'FAIL: UPDATE renglon_comprobante rechazada con % (se esperaba 42501): %', SQLSTATE, SQLERRM;
        END IF;
        RAISE NOTICE 'OK (B): UPDATE renglon_comprobante como app_rw denegado (42501)';
    END;

    BEGIN
        DELETE FROM renglon_comprobante
         WHERE nro_comprobante < 0;
        RAISE EXCEPTION 'FAIL: app_rw hizo DELETE sobre renglon_comprobante sin recibir error';
    EXCEPTION WHEN others THEN
        IF SQLSTATE IS DISTINCT FROM '42501' THEN
            RAISE EXCEPTION 'FAIL: DELETE renglon_comprobante rechazada con % (se esperaba 42501): %', SQLSTATE, SQLERRM;
        END IF;
        RAISE NOTICE 'OK (B): DELETE renglon_comprobante como app_rw denegado (42501)';
    END;

    RESET ROLE;
    PERFORM pg_temp.t7_priv('app_rw', 'renglon_comprobante', 'UPDATE', false);
    PERFORM pg_temp.t7_priv('app_rw', 'renglon_comprobante', 'DELETE', false);
    RAISE NOTICE 'OK (B): 007 no concede UPDATE ni DELETE de renglon_comprobante a app_rw';

    -- T1 (BEFORE INSERT de renglon_comprobante) hace FOR UPDATE sobre
    -- stock_sala, pero es SECURITY DEFINER: corre con los permisos del
    -- owner. app_rw no necesita UPDATE sobre stock_sala; la venta se
    -- verifica funcionalmente en la sección F.
    PERFORM pg_temp.t7_priv('app_rw', 'stock_sala', 'UPDATE', false);
    RAISE NOTICE 'OK (B): app_rw no tiene UPDATE en stock_sala (T1 es SECURITY DEFINER)';

    ---------------------------------------------------------------------------
    -- C. reporte_ro: solo lectura. Muestras de INSERT/UPDATE/DELETE sobre
    --    representativas (vino, comprobante, stock_sala) deben fallar 42501.
    ---------------------------------------------------------------------------
    PERFORM set_config('role', 'reporte_ro', true);

    BEGIN
        UPDATE vino SET precio_venta = precio_venta WHERE cod_vino < 0;
        RAISE EXCEPTION 'FAIL: reporte_ro hizo UPDATE sobre vino sin recibir error';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (C): UPDATE vino como reporte_ro denegado (42501)';
    END;

    BEGIN
        DELETE FROM comprobante WHERE nro_comprobante < 0;
        RAISE EXCEPTION 'FAIL: reporte_ro hizo DELETE sobre comprobante sin recibir error';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (C): DELETE comprobante como reporte_ro denegado (42501)';
    END;

    BEGIN
        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (9101, 0, 1);
        RAISE EXCEPTION 'FAIL: reporte_ro hizo INSERT sobre stock_sala sin recibir error';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (C): INSERT stock_sala como reporte_ro denegado (42501)';
    END;

    RESET ROLE;

    ---------------------------------------------------------------------------
    -- D. Sin fugas por PUBLIC: rol probe transitorio y escaneo de ACLs.
    ---------------------------------------------------------------------------
    CREATE ROLE probe_public_leak_007 NOLOGIN;

    PERFORM set_config('role', 'probe_public_leak_007', true);

    -- Sin USAGE sobre el esquema public, la relación no llega a existir para
    -- el rol probe: PostgreSQL 16 la deja invisible (42P01) o, si el rol
    -- tiene usage heredado, deniega el acceso (42501). Ambas son pruebas de
    -- que no hay fuga; cualquier otro error aborta la prueba.
    DECLARE v_probe integer;
    BEGIN
        SELECT cod_vino INTO v_probe FROM vino LIMIT 1;
        RAISE EXCEPTION 'FAIL: el rol probe de PUBLIC pudo SELECT sobre vino';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'OK (D): SELECT vino como rol de PUBLIC denegado (42501)';
        WHEN undefined_table THEN
            RAISE NOTICE 'OK (D): vino invisible para el rol de PUBLIC (42P01, sin USAGE del esquema)';
    END;

    DECLARE v_probe integer;
    BEGIN
        SELECT cod_vino INTO v_probe FROM vw_stock_total_vino LIMIT 1;
        RAISE EXCEPTION 'FAIL: el rol probe de PUBLIC pudo SELECT sobre vw_stock_total_vino';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'OK (D): SELECT vw_stock_total_vino como rol de PUBLIC denegado (42501)';
        WHEN undefined_table THEN
            RAISE NOTICE 'OK (D): vw_stock_total_vino invisible para el rol de PUBLIC (42P01, sin USAGE del esquema)';
    END;
    RESET ROLE;

    -- Ninguna ACL de tablas, vistas o secuencias del esquema public concede
    -- algo a grantee 0 (PUBLIC).
    IF EXISTS (
        SELECT 1
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
         WHERE n.nspname = 'public'
           AND c.relkind IN ('r', 'v', 'S', 'f', 'p', 'm')
           AND a.grantee = 0
    ) THEN
        RAISE EXCEPTION 'FAIL: hay tablas, vistas o secuencias con privilegios para PUBLIC (grantee 0) en el esquema public';
    END IF;

    -- Ninguna rutina del esquema public concede EXECUTE a PUBLIC.
    IF EXISTS (
        SELECT 1
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
         WHERE n.nspname = 'public'
           AND a.grantee = 0
    ) THEN
        RAISE EXCEPTION 'FAIL: hay rutinas con EXECUTE para PUBLIC (grantee 0) en el esquema public';
    END IF;

    -- El esquema public en si no concede USAGE ni CREATE a PUBLIC.
    IF EXISTS (
        SELECT 1
          FROM pg_namespace n
         CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a
         WHERE n.nspname = 'public'
           AND a.grantee = 0
    ) THEN
        RAISE EXCEPTION 'FAIL: el esquema public conserva privilegios para PUBLIC (grantee 0)';
    END IF;

    RAISE NOTICE 'OK (D): sin privilegios para PUBLIC en rol probe, tablas, vistas, secuencias, rutinas ni esquema';

    ---------------------------------------------------------------------------
    -- E. Sin privilegios por defecto ocultos y sin herencia de roles.
    ---------------------------------------------------------------------------
    -- pg_default_acl: ninguna entrada debe conceder INSERT/UPDATE/DELETE a
    -- app_rw (las tablas futuras escribibles exigen GRANT explicito), ni
    -- escrituras a reporte_ro.
    IF EXISTS (
        SELECT 1
          FROM pg_default_acl d
         CROSS JOIN LATERAL aclexplode(d.defaclacl) a
         WHERE a.grantee = 'app_rw'::regrole
           AND a.privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
    ) THEN
        RAISE EXCEPTION 'FAIL: existen privilegios de escritura por defecto para app_rw (pg_default_acl)';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_default_acl d
         CROSS JOIN LATERAL aclexplode(d.defaclacl) a
         WHERE a.grantee = 'reporte_ro'::regrole
           AND a.privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
    ) THEN
        RAISE EXCEPTION 'FAIL: existen privilegios de escritura por defecto para reporte_ro (pg_default_acl)';
    END IF;

    -- pg_auth_members: app_rw y reporte_ro no heredan ningún rol.
    IF EXISTS (
        SELECT 1
          FROM pg_auth_members m
          JOIN pg_roles r ON r.oid = m.member
         WHERE r.rolname IN ('app_rw', 'reporte_ro')
    ) THEN
        RAISE EXCEPTION 'FAIL: app_rw o reporte_ro son miembros de otro rol (pg_auth_members)';
    END IF;

    RAISE NOTICE 'OK (E): sin escrituras por defecto para app_rw/reporte_ro y sin herencia de roles';
END $$;

-- -----------------------------------------------------------------------------
-- F. Humo del lado permitido como app_rw.
--    Catálogos que la API no crea, sembrados como superusuario (rol del
--    proceso de carga de P2); el camino de escritura de la API corre como
--    app_rw con IDs 91xx.
-- -----------------------------------------------------------------------------
INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
VALUES (9101, '5600', 'Localidad Test 007', 'Mendoza', 'Encargado Test 007');

INSERT INTO cepa (id_cepa, nombre, tipo)
VALUES (9101, 'Malbec Test 007', 'tinta');

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20000000091', 'Bodega Test 007', 'Calle Bodega 007');

INSERT INTO transportista (id_transportista, razon_social, cuit, email, telefono, domicilio)
VALUES (9101, 'Transportista Test 007', '20000000026', 'test007@test.com', '2620000007', 'Calle Transporte 007');

INSERT INTO sala (id_sala, direccion, dia_cierre_semanal, id_localidad)
VALUES (9101, 'Sala Test 007', 2, 9101);

-- Alinea las secuencias identity con los ids ya presentes antes de que el
-- fixture inserte sin id explícito. db_tests.sql siembra filas con ids
-- explícitos sin avanzar la secuencia; sin este ajuste, el primer INSERT por
-- identity devuelve un id ocupado y colisiona en la PK. setval(seq, MAX(id))
-- garantiza que el siguiente valor supere a toda fila existente, sin importar
-- dónde estuviera la secuencia. En una base recién inicializada no hay filas y
-- no se toca nada, así que el comportamiento sobre base limpia no cambia.
-- Corre como superusuario, antes del SET ROLE app_rw, porque setval exige
-- UPDATE sobre la secuencia y app_rw no lo tiene.
DO $$
DECLARE
    s record;
BEGIN
    FOR s IN
        SELECT 'cliente_id_cliente_seq'::text           AS seq,
               COALESCE(MAX(id_cliente), 0)             AS mx FROM cliente
        UNION ALL
        SELECT 'vino_cod_vino_seq',        COALESCE(MAX(cod_vino), 0)        FROM vino
        UNION ALL
        SELECT 'comprobante_nro_comprobante_seq',
               COALESCE(MAX(nro_comprobante), 0)                             FROM comprobante
        UNION ALL
        SELECT 'ingreso_cod_ingreso_seq',  COALESCE(MAX(cod_ingreso), 0)     FROM ingreso
        UNION ALL
        SELECT 'transferencia_nro_solicitud_seq',
               COALESCE(MAX(nro_solicitud), 0)                               FROM transferencia
    LOOP
        IF s.mx > 0 THEN
            PERFORM setval(s.seq, s.mx);
        END IF;
    END LOOP;
END $$;

DO $$
DECLARE
    v_cliente integer;
    v_vino_a  integer;
    v_vino_b  integer;
    v_nro     integer;
    v_ingreso integer;
    v_transf  integer;
    v_stock_sala_a integer := 10;  -- cantidad sembrada para el vino A
BEGIN
    PERFORM set_config('role', 'app_rw', true);

    -- F1. Alta de cliente socio y vino con composición (100 % con una cepa)
    --     por el camino normal de la API. descuento es GENERATED ALWAYS AS
    --     (fn_descuento_cliente(tipo)) STORED: NO se inserta y la base lo
    --     calcula (RN-06).
    INSERT INTO cliente (nombre, tipo, tipo_documento, nro_documento,
                         direccion, id_localidad)
    VALUES ('Cliente Test 007', 'socio', 'DNI', '91000001',
            'Calle Cliente 007', 9101)
    RETURNING id_cliente INTO v_cliente;

    IF v_cliente IS NULL THEN
        RAISE EXCEPTION 'FAIL: cliente no devolvio id (secuencia de cliente no usable por app_rw)';
    END IF;

    IF (SELECT descuento FROM cliente WHERE id_cliente = v_cliente)
           IS DISTINCT FROM fn_descuento_cliente('socio') THEN
        RAISE EXCEPTION 'FAIL: descuento generado del cliente es %, esperado fn_descuento_cliente(socio) = %',
            (SELECT descuento FROM cliente WHERE id_cliente = v_cliente),
            fn_descuento_cliente('socio');
    END IF;

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml,
                      graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Test 007 A', 'tinto', 2021, 750, 13.50, 1000.00,
            '20000000091')
    RETURNING cod_vino INTO v_vino_a;

    INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
    VALUES (v_vino_a, 9101, 100.00);

    -- F2. Venta como app_rw. El stock inicial de la sala lo siembra el rol de
    --     carga (superusuario): app_rw ya no tiene INSERT sobre stock_sala,
    --     porque sus escrituras las hacen T1/T2 y sp_procesar_* (DEFINER).
    PERFORM set_config('role', 'none', true);
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    VALUES (9101, v_vino_a, v_stock_sala_a);
    PERFORM set_config('role', 'app_rw', true);

    INSERT INTO comprobante (id_cliente, id_sala)
    VALUES (v_cliente, 9101)
    RETURNING nro_comprobante INTO v_nro;

    -- renglón: precio 1000, socio 10 % → subtotal 1800.00, descuento 200.00.
    -- T2 (AFTER INSERT, SECURITY DEFINER: corre con los permisos del dueño,
    -- no con los de app_rw) recalcula la cabecera y descuenta stock: 10 → 8.
    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_nro, v_vino_a, 2);

    IF (SELECT total FROM comprobante WHERE nro_comprobante = v_nro)
           <> 1800.00 THEN
        RAISE EXCEPTION 'FAIL: total recalculado por T2 es %, esperado 1800.00',
            (SELECT total FROM comprobante WHERE nro_comprobante = v_nro);
    END IF;

    IF (SELECT cantidad FROM stock_sala
         WHERE id_sala = 9101 AND cod_vino = v_vino_a) <> 8 THEN
        RAISE EXCEPTION 'FAIL: stock de sala tras la venta es %, esperado 8',
            (SELECT cantidad FROM stock_sala
              WHERE id_sala = 9101 AND cod_vino = v_vino_a);
    END IF;
    RAISE NOTICE 'OK (F): venta como app_rw recalcula total 1800.00 y descuenta stock 10 → 8';

    -- F3. Ingreso: alta, renglón, terminar y procesar como app_rw.
    --     sp_procesar_ingreso es SECURITY DEFINER: hace FOR UPDATE sobre la
    --     cabecera y upsert sobre stock_deposito con permisos del owner, por
    --     eso app_rw no necesita UPDATE en stock_deposito.
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml,
                      graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Test 007 B', 'tinto', 2022, 750, 12.00, 100.00,
            '20000000091')
    RETURNING cod_vino INTO v_vino_b;

    INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
    VALUES (v_vino_b, 9101, 100.00);

    INSERT INTO ingreso (id_transportista, cuit_bodega)
    VALUES (9101, '20000000091')
    RETURNING cod_ingreso INTO v_ingreso;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_ingreso, v_vino_b, 5);

    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ingreso;

    CALL sp_procesar_ingreso(v_ingreso);

    IF (SELECT cantidad FROM stock_deposito WHERE cod_vino = v_vino_b)
           IS DISTINCT FROM 5 THEN
        RAISE EXCEPTION 'FAIL: stock_deposito tras procesar ingreso es %, esperado 5',
            (SELECT cantidad FROM stock_deposito WHERE cod_vino = v_vino_b);
    END IF;

    IF (SELECT estado::text FROM ingreso WHERE cod_ingreso = v_ingreso)
           <> 'procesado' THEN
        RAISE EXCEPTION 'FAIL: estado del ingreso tras procesar es %, esperado procesado',
            (SELECT estado::text FROM ingreso WHERE cod_ingreso = v_ingreso);
    END IF;
    RAISE NOTICE 'OK (F): CALL sp_procesar_ingreso como app_rw suma stock_deposito 5 y pasa a procesado';

    -- F4. Transferencia: el FOR UPDATE de renglones y de stock lo hace
    --     sp_procesar_transferencia como SECURITY DEFINER (owner); app_rw no
    --     necesita UPDATE de tabla completa sobre renglon_transferencia.
    INSERT INTO transferencia (id_sala)
    VALUES (9101)
    RETURNING nro_solicitud INTO v_transf;

    INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
    VALUES (v_transf, v_vino_b, 3);

    UPDATE transferencia SET estado = 'terminado'
     WHERE nro_solicitud = v_transf;

    CALL sp_procesar_transferencia(v_transf);

    IF (SELECT cantidad FROM stock_deposito WHERE cod_vino = v_vino_b)
           IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'FAIL: stock_deposito tras procesar transferencia es %, esperado 2',
            (SELECT cantidad FROM stock_deposito WHERE cod_vino = v_vino_b);
    END IF;

    IF (SELECT cantidad FROM stock_sala
         WHERE id_sala = 9101 AND cod_vino = v_vino_b) IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'FAIL: stock_sala tras procesar transferencia es %, esperado 3',
            (SELECT cantidad FROM stock_sala
              WHERE id_sala = 9101 AND cod_vino = v_vino_b);
    END IF;
    RAISE NOTICE 'OK (F): CALL sp_procesar_transferencia como app_rw descuenta deposito 5 → 2 y suma sala → 3';

    -- F5. Cambio de precio del vino B: el trigger T7 (AFTER UPDATE de vino,
    --     SECURITY DEFINER) inserta auditoria_precio con permisos del owner;
    --     app_rw solo conserva SELECT sobre esa tabla.
    IF (SELECT COUNT(*) FROM auditoria_precio
         WHERE cod_vino = v_vino_b) <> 0 THEN
        RAISE EXCEPTION 'FAIL: auditoria_precio tenia filas antes del cambio de precio del vino B';
    END IF;

    UPDATE vino SET precio_venta = 110.00 WHERE cod_vino = v_vino_b;

    IF (SELECT COUNT(*) FROM auditoria_precio
         WHERE cod_vino = v_vino_b
           AND precio_anterior = 100.00
           AND precio_nuevo = 110.00) <> 1 THEN
        RAISE EXCEPTION 'FAIL: auditoria_precio no registro exactamente el cambio 100.00 → 110.00 del vino B';
    END IF;
    RAISE NOTICE 'OK (F): UPDATE de precio como app_rw dispara T7 y audita 100.00 → 110.00';

    -- F6. EXECUTE de las rutinas del contrato API como app_rw.
    IF fn_descuento_cliente('socio') <> 10.00 THEN
        RAISE EXCEPTION 'FAIL: fn_descuento_cliente(socio) devolvio %, esperado 10.00',
            fn_descuento_cliente('socio');
    END IF;

    IF fn_stock_sala(9101, v_vino_b) <> 3 THEN
        RAISE EXCEPTION 'FAIL: fn_stock_sala devolvio %, esperado 3',
            fn_stock_sala(9101, v_vino_b);
    END IF;

    -- Los valores esperados son literales derivados de CURRENT_DATE: la suite
    -- no depende del año calendario.
    IF fn_antiguedad_anios(CURRENT_DATE) <> 0 THEN
        RAISE EXCEPTION 'FAIL: fn_antiguedad_anios(CURRENT_DATE) devolvio %, esperado 0',
            fn_antiguedad_anios(CURRENT_DATE);
    END IF;

    IF fn_antiguedad_anios((CURRENT_DATE + INTERVAL '5 years')::date) <> 0 THEN
        RAISE EXCEPTION 'FAIL: fn_antiguedad_anios(futuro +5 anios) devolvio %, esperado 0',
            fn_antiguedad_anios((CURRENT_DATE + INTERVAL '5 years')::date);
    END IF;

    IF fn_antiguedad_anios((CURRENT_DATE - INTERVAL '3 years')::date) <> 3 THEN
        RAISE EXCEPTION 'FAIL: fn_antiguedad_anios(CURRENT_DATE - 3 anios) devolvio %, esperado 3',
            fn_antiguedad_anios((CURRENT_DATE - INTERVAL '3 years')::date);
    END IF;

    IF fn_antiguedad_anios(NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: fn_antiguedad_anios(NULL) devolvio %, esperado NULL (STRICT)',
            fn_antiguedad_anios(NULL);
    END IF;

    IF (SELECT total FROM fn_total_comprobante(v_nro)) IS DISTINCT FROM 1800.00 THEN
        RAISE EXCEPTION 'FAIL: fn_total_comprobante devolvio %, esperado total 1800.00',
            (SELECT total FROM fn_total_comprobante(v_nro));
    END IF;
    RAISE NOTICE 'OK (F): EXECUTE de las 4 rutinas de consulta del contrato como app_rw';

    RESET ROLE;
END $$;

-- -----------------------------------------------------------------------------
-- G. Denegaciones por columna como app_rw (R-001/R-005/R-012).
--    Toda columna fuera de la matriz debe fallar con 42501 aunque la tabla
--    tenga otros privilegios; el chequeo ocurre al iniciar el plan, así que
--    un WHERE que no alcanza filas no lo evita.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM set_config('role', 'app_rw', true);

    BEGIN
        UPDATE comprobante SET total = 0 WHERE nro_comprobante < 0;
        RAISE EXCEPTION 'FAIL: app_rw pudo UPDATE comprobante.total';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (G): UPDATE comprobante.total como app_rw denegado (42501)';
    END;

    BEGIN
        UPDATE ingreso SET fecha = fecha WHERE cod_ingreso < 0;
        RAISE EXCEPTION 'FAIL: app_rw pudo UPDATE ingreso.fecha';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (G): UPDATE ingreso.fecha como app_rw denegado (42501)';
    END;

    BEGIN
        UPDATE transferencia SET fecha_confeccion = fecha_confeccion
         WHERE nro_solicitud < 0;
        RAISE EXCEPTION 'FAIL: app_rw pudo UPDATE transferencia.fecha_confeccion';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (G): UPDATE transferencia.fecha_confeccion como app_rw denegado (42501)';
    END;

    BEGIN
        UPDATE stock_sala SET cantidad = cantidad WHERE id_sala < 0;
        RAISE EXCEPTION 'FAIL: app_rw pudo UPDATE stock_sala.cantidad';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (G): UPDATE stock_sala.cantidad como app_rw denegado (42501)';
    END;

    BEGIN
        UPDATE stock_deposito SET cantidad = cantidad WHERE cod_vino < 0;
        RAISE EXCEPTION 'FAIL: app_rw pudo UPDATE stock_deposito.cantidad';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (G): UPDATE stock_deposito.cantidad como app_rw denegado (42501)';
    END;

    BEGIN
        UPDATE renglon_ingreso SET cod_vino = cod_vino WHERE cod_ingreso < 0;
        RAISE EXCEPTION 'FAIL: app_rw pudo UPDATE renglon_ingreso.cod_vino';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (G): UPDATE renglon_ingreso.cod_vino como app_rw denegado (42501)';
    END;

    BEGIN
        INSERT INTO comprobante (fecha, id_cliente, id_sala, total)
        VALUES (CURRENT_DATE, 9101, 9101, 0);
        RAISE EXCEPTION 'FAIL: app_rw pudo INSERT comprobante.total';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (G): INSERT comprobante.total como app_rw denegado (42501)';
    END;

    BEGIN
        INSERT INTO auditoria_precio
            (cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
        VALUES (0, 0, 0, now(), 'test_007');
        RAISE EXCEPTION 'FAIL: app_rw pudo INSERT auditoria_precio';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (G): INSERT auditoria_precio como app_rw denegado (42501)';
    END;

    PERFORM set_config('role', 'none', true);
END $$;

-- -----------------------------------------------------------------------------
-- H. Columnas permitidas: los UPDATE por columna de la matriz deben pasar el
--    chequeo de privilegio (pueden afectar 0 filas, eso no importa).
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM set_config('role', 'app_rw', true);

    UPDATE ingreso SET estado = estado WHERE cod_ingreso < 0;
    UPDATE transferencia SET estado = estado WHERE nro_solicitud < 0;
    UPDATE renglon_ingreso SET cantidad = cantidad WHERE cod_ingreso < 0;
    UPDATE renglon_transferencia SET cantidad = cantidad WHERE nro_solicitud < 0;

    PERFORM set_config('role', 'none', true);
    RAISE NOTICE 'OK (H): UPDATE(estado)/UPDATE(cantidad) permitidos a app_rw';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE EXCEPTION 'FAIL: app_rw no pudo ejercer un UPDATE por columna permitido: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- I. Secuencias (R-013): app_rw no tiene USAGE en ninguna de las 13 y aun
--    así puede insertar con PK identity BY DEFAULT (cliente) y ALWAYS (vino).
--    cepa también es BY DEFAULT, pero app_rw no puede insertarla (es un
--    catálogo de carga); la prueba usa una tabla que sí está en su matriz.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    c_seqs text[] := ARRAY[
        'localidad_id_localidad_seq', 'cepa_id_cepa_seq',
        'transportista_id_transportista_seq', 'maridaje_id_maridaje_seq',
        'finca_id_finca_seq', 'sala_id_sala_seq', 'cliente_id_cliente_seq',
        'analisis_calidad_id_analisis_seq', 'auditoria_precio_id_auditoria_seq',
        'comprobante_nro_comprobante_seq', 'ingreso_cod_ingreso_seq',
        'transferencia_nro_solicitud_seq', 'vino_cod_vino_seq'];
    r            text;
    v_cliente    integer;
    v_vino       integer;
BEGIN
    FOREACH r IN ARRAY c_seqs LOOP
        IF has_sequence_privilege('app_rw', r, 'USAGE') THEN
            RAISE EXCEPTION 'FAIL: app_rw conserva USAGE sobre la secuencia %', r;
        END IF;
    END LOOP;

    PERFORM set_config('role', 'app_rw', true);

    -- cliente.id_cliente es GENERATED BY DEFAULT AS IDENTITY.
    INSERT INTO cliente (nombre, tipo, tipo_documento, nro_documento,
                         direccion, id_localidad)
    VALUES ('Cliente Test 007 Seq', 'socio', 'DNI', '91000002',
            'Calle Cliente Seq 007', 9101)
    RETURNING id_cliente INTO v_cliente;

    -- vino.cod_vino es GENERATED ALWAYS AS IDENTITY.
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml,
                      graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Test 007 Seq', 'tinto', 2023, 750, 13.00, 100.00,
            '20000000091')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
    VALUES (v_vino, 9101, 100.00);

    PERFORM set_config('role', 'none', true);

    IF v_cliente IS NULL OR v_vino IS NULL THEN
        RAISE EXCEPTION 'FAIL: la PK identity no se generó sin USAGE de secuencia (cliente=%, vino=%)',
            v_cliente, v_vino;
    END IF;

    RAISE NOTICE 'OK (I): app_rw sin USAGE de secuencia e INSERT identity BY DEFAULT/ALWAYS correcto';
END $$;

-- -----------------------------------------------------------------------------
-- J. reporte_ro (R-011): las 4 vistas se leen solo con el GRANT de vista
--    aunque se revoque SELECT sobre TODAS las tablas del esquema (el acceso
--    a las tablas base se valida con el owner de la vista). Una tabla no
--    habilitada, en cambio, debe fallar con 42501. Todo en un SAVEPOINT que
--    se revierte para no alterar el resto de la prueba.
-- -----------------------------------------------------------------------------
SAVEPOINT rep_ro_views;

-- Se revoca SELECT sobre las 29 tablas BASE (las vistas conservan su GRANT).
REVOKE SELECT ON TABLE localidad, cepa, bodega, transportista, maridaje,
    finca, sala, empleado, parcela, vino, cliente, lote_uva, composicion,
    vino_maridaje, socio, distribuidor, exportador, permiso_exportacion,
    transportista_localidad, analisis_calidad, auditoria_precio, comprobante,
    renglon_comprobante, ingreso, renglon_ingreso, transferencia,
    renglon_transferencia, stock_deposito, stock_sala
    FROM reporte_ro;

DO $$
DECLARE
    v_n bigint;
BEGIN
    PERFORM set_config('role', 'reporte_ro', true);

    SELECT count(*) INTO v_n FROM vw_stock_total_vino;
    SELECT count(*) INTO v_n FROM vw_ventas_mensuales_sala;
    SELECT count(*) INTO v_n FROM vw_documentos_pendientes;
    SELECT count(*) INTO v_n FROM vw_ficha_vino;

    BEGIN
        SELECT count(*) INTO v_n FROM cliente;
        RAISE EXCEPTION 'FAIL: reporte_ro pudo SELECT sobre cliente';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK (J): SELECT cliente como reporte_ro denegado (42501)';
    END;

    PERFORM set_config('role', 'none', true);
    RAISE NOTICE 'OK (J): reporte_ro lee las 4 vistas con las tablas base revocadas';
END $$;

ROLLBACK TO SAVEPOINT rep_ro_views;
RELEASE SAVEPOINT rep_ro_views;

DO $$
BEGIN
    IF NOT has_table_privilege('reporte_ro', 'vw_ficha_vino', 'SELECT')
       OR NOT has_table_privilege('reporte_ro', 'vw_ventas_mensuales_sala', 'SELECT') THEN
        RAISE EXCEPTION 'FAIL: el rollback del REVOKE no restauró SELECT de reporte_ro sobre las vistas';
    END IF;
    RAISE NOTICE 'OK (J): el GRANT de vista de reporte_ro quedó restaurado';
END $$;

-- -----------------------------------------------------------------------------
-- K. Idempotencia y persistencia de ACL.
--    K1: re-aplicar las sentencias de 007 (mismas listas de la matriz) no
--        produce error y deja exactamente la misma ACL.
--    K2: re-aplicar 006 (CREATE OR REPLACE VIEW) preserva la ACL de las
--        vistas, incluidos los GRANT de app_rw y reporte_ro.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    c_todas    text[] := ARRAY[
        'localidad', 'cepa', 'bodega', 'transportista', 'maridaje', 'finca',
        'sala', 'empleado', 'parcela', 'vino', 'cliente', 'lote_uva',
        'composicion', 'vino_maridaje', 'socio', 'distribuidor', 'exportador',
        'permiso_exportacion', 'transportista_localidad', 'analisis_calidad',
        'auditoria_precio', 'comprobante', 'renglon_comprobante', 'ingreso',
        'renglon_ingreso', 'transferencia', 'renglon_transferencia',
        'stock_deposito', 'stock_sala'];
    c_vistas   text[] := ARRAY[
        'vw_stock_total_vino', 'vw_ventas_mensuales_sala',
        'vw_documentos_pendientes', 'vw_ficha_vino'];
    c_seqs     text[] := ARRAY[
        'localidad_id_localidad_seq', 'cepa_id_cepa_seq',
        'transportista_id_transportista_seq', 'maridaje_id_maridaje_seq',
        'finca_id_finca_seq', 'sala_id_sala_seq', 'cliente_id_cliente_seq',
        'analisis_calidad_id_analisis_seq', 'auditoria_precio_id_auditoria_seq',
        'comprobante_nro_comprobante_seq', 'ingreso_cod_ingreso_seq',
        'transferencia_nro_solicitud_seq', 'vino_cod_vino_seq'];
    c_rtines   text[] := ARRAY[
        'fn_descuento_cliente(varchar)',
        'fn_stock_sala(integer, integer)',
        'fn_antiguedad_anios(date)',
        'fn_total_comprobante(integer)',
        'sp_procesar_ingreso(integer)',
        'sp_procesar_transferencia(integer)',
        'fn_tg_renglon_venta_completar()',
        'fn_tg_renglon_venta_actualizar()',
        'fn_tg_ingreso_estado()',
        'fn_tg_transferencia_estado()',
        'fn_tg_transferencia_fecha()',
        'fn_tg_renglon_documento_bloqueo()',
        'fn_tg_vino_precio_auditoria()',
        'fn_tg_composicion_cien()',
        'fn_tg_renglon_venta_inmutable()'];
    c_rtines_api text[] := ARRAY[
        'fn_descuento_cliente(varchar)',
        'fn_stock_sala(integer, integer)',
        'fn_antiguedad_anios(date)',
        'fn_total_comprobante(integer)',
        'sp_procesar_ingreso(integer)',
        'sp_procesar_transferencia(integer)'];
    c_app_ins  text[] := ARRAY[
        'vino', 'cliente', 'composicion', 'vino_maridaje', 'socio',
        'distribuidor', 'exportador', 'permiso_exportacion'];
    c_app_upd  text[] := ARRAY['vino', 'cliente', 'distribuidor', 'exportador'];
    c_app_del  text[] := ARRAY[
        'vino', 'cliente', 'composicion', 'vino_maridaje',
        'permiso_exportacion'];
    c_rep_sel  text[] := ARRAY[
        'vino', 'renglon_comprobante', 'stock_sala', 'stock_deposito',
        'transportista', 'ingreso'];
    v_before   text;
    v_after    text;
    v_acl_v    text;
    v_acl_v2   text;
    v_def      text;
    r          text;
BEGIN
    -- K1. Snapshot ampliado: ACL de tablas, vistas, secuencias y rutinas,
    --     ACL por columna (pg_attribute.attacl), privilegios por defecto,
    --     esquema, base, membresías y atributos de los tres roles.
    --
    --     Re-ejecuta: la matriz de REVOKE/GRANT por objeto, incluidos los
    --     GRANT por columna. Sobre eso aplica la comparación: si re-aplicar
    --     cambiara cualquier ACL de objeto o de columna, el md5 cambiaría.
    --
    --     NO re-ejecuta: CREATE ROLE, REVOKE ALL ON SCHEMA / ON DATABASE ni
    --     ALTER DEFAULT PRIVILEGES. Eso queda cubierto al re-aplicar el
    --     archivo 007_roles.sql completo, verificado fuera de esta suite, y el
    --     comportamiento del ALTER DEFAULT PRIVILEGES de rutinas se asierta
    --     directamente en la sección L.
    --
    --     Componentes de estabilidad, no de idempotencia: pg_default_acl,
    --     nspacl, datacl, pg_auth_members y los atributos de rol están en el
    --     hash pero la re-aplicación no los toca, así que siempre coinciden.
    --     Sirven para detectar un cambio externo durante la corrida, no para
    --     probar que 007 es idempotente sobre ellos.
    SELECT md5(string_agg(x, ',' ORDER BY x)) INTO v_before
      FROM (
        SELECT c.relname || '=' || COALESCE(c.relacl::text, '-') AS x
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'S', 'm', 'f', 'p')
        UNION ALL
        SELECT c.relname || '.' || a.attname || '=' || COALESCE(a.attacl::text, '-')
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND a.attacl IS NOT NULL
        UNION ALL
        SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' ||
               COALESCE(p.proacl::text, '-')
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
        UNION ALL
        SELECT '<default:' || defaclobjtype::text || '>' ||
               COALESCE(defaclacl::text, '-')
          FROM pg_default_acl
        UNION ALL
        SELECT '<schema:public>' || COALESCE(nspacl::text, '-')
          FROM pg_namespace
         WHERE nspname = 'public'
        UNION ALL
        SELECT '<db>' || COALESCE(datacl::text, '-')
          FROM pg_database
         WHERE datname = current_database()
        UNION ALL
        SELECT '<member>' || member::regrole::text || '=>' || roleid::regrole::text
          FROM pg_auth_members
        UNION ALL
        SELECT '<role>' || rolname || ':' || rolinherit::text ||
               rolcreatedb::text || rolcreaterole::text ||
               rolcanlogin::text || rolbypassrls::text
          FROM pg_roles
         WHERE rolname IN ('bda_owner', 'app_rw', 'reporte_ro')
      ) AS s;

    -- Re-aplicar la matriz de 007 (mismas listas que la sección A).
    FOREACH r IN ARRAY c_todas LOOP
        EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE %I FROM PUBLIC', r);
        EXECUTE format('GRANT SELECT ON TABLE %I TO app_rw', r);
        IF r = ANY (c_app_ins) THEN
            EXECUTE format('GRANT INSERT ON TABLE %I TO app_rw', r);
        END IF;
        IF r = ANY (c_app_upd) THEN
            EXECUTE format('GRANT UPDATE ON TABLE %I TO app_rw', r);
        END IF;
        IF r = ANY (c_app_del) THEN
            EXECUTE format('GRANT DELETE ON TABLE %I TO app_rw', r);
        END IF;
        IF r = ANY (c_rep_sel) THEN
            EXECUTE format('GRANT SELECT ON TABLE %I TO reporte_ro', r);
        ELSE
            EXECUTE format('REVOKE SELECT ON TABLE %I FROM reporte_ro', r);
        END IF;
    END LOOP;

    EXECUTE 'GRANT INSERT (fecha, id_cliente, id_sala) ON TABLE comprobante TO app_rw';
    EXECUTE 'GRANT INSERT (nro_comprobante, cod_vino, cantidad) ON TABLE renglon_comprobante TO app_rw';
    EXECUTE 'GRANT INSERT (fecha, id_transportista, cuit_bodega) ON TABLE ingreso TO app_rw';
    EXECUTE 'GRANT INSERT (id_sala) ON TABLE transferencia TO app_rw';
    EXECUTE 'GRANT INSERT (cod_ingreso, cod_vino, cantidad) ON TABLE renglon_ingreso TO app_rw';
    EXECUTE 'GRANT INSERT (nro_solicitud, cod_vino, cantidad) ON TABLE renglon_transferencia TO app_rw';
    EXECUTE 'GRANT UPDATE (estado) ON TABLE ingreso TO app_rw';
    EXECUTE 'GRANT UPDATE (estado) ON TABLE transferencia TO app_rw';
    EXECUTE 'GRANT UPDATE (cantidad) ON TABLE renglon_ingreso, renglon_transferencia TO app_rw';

    FOREACH r IN ARRAY c_vistas LOOP
        EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE %I FROM PUBLIC', r);
        EXECUTE format('GRANT SELECT ON TABLE %I TO app_rw', r);
        EXECUTE format('GRANT SELECT ON TABLE %I TO reporte_ro', r);
    END LOOP;

    FOREACH r IN ARRAY c_seqs LOOP
        EXECUTE format('REVOKE ALL PRIVILEGES ON SEQUENCE %I FROM PUBLIC', r);
        EXECUTE format('REVOKE USAGE ON SEQUENCE %I FROM app_rw', r);
        EXECUTE format('GRANT ALL PRIVILEGES ON SEQUENCE %I TO bda_owner', r);
    END LOOP;

    FOREACH r IN ARRAY c_rtines LOOP
        EXECUTE format('REVOKE ALL PRIVILEGES ON ROUTINE %s FROM PUBLIC', r);
        EXECUTE format('GRANT ALL PRIVILEGES ON ROUTINE %s TO bda_owner', r);
    END LOOP;

    FOREACH r IN ARRAY c_rtines_api LOOP
        EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO app_rw', r);
    END LOOP;

    SELECT md5(string_agg(x, ',' ORDER BY x)) INTO v_after
      FROM (
        SELECT c.relname || '=' || COALESCE(c.relacl::text, '-') AS x
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'S', 'm', 'f', 'p')
        UNION ALL
        SELECT c.relname || '.' || a.attname || '=' || COALESCE(a.attacl::text, '-')
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND a.attacl IS NOT NULL
        UNION ALL
        SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' ||
               COALESCE(p.proacl::text, '-')
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
        UNION ALL
        SELECT '<default:' || defaclobjtype::text || '>' ||
               COALESCE(defaclacl::text, '-')
          FROM pg_default_acl
        UNION ALL
        SELECT '<schema:public>' || COALESCE(nspacl::text, '-')
          FROM pg_namespace
         WHERE nspname = 'public'
        UNION ALL
        SELECT '<db>' || COALESCE(datacl::text, '-')
          FROM pg_database
         WHERE datname = current_database()
        UNION ALL
        SELECT '<member>' || member::regrole::text || '=>' || roleid::regrole::text
          FROM pg_auth_members
        UNION ALL
        SELECT '<role>' || rolname || ':' || rolinherit::text ||
               rolcreatedb::text || rolcreaterole::text ||
               rolcanlogin::text || rolbypassrls::text
          FROM pg_roles
         WHERE rolname IN ('bda_owner', 'app_rw', 'reporte_ro')
      ) AS s;

    IF v_before IS DISTINCT FROM v_after THEN
        RAISE EXCEPTION 'FAIL: re-aplicar 007 cambió la ACL (% vs %)', v_before, v_after;
    END IF;
    RAISE NOTICE 'OK (K1): re-aplicar la matriz por objeto de 007 no altera ninguna ACL de objeto ni de columna';

    -- K2. Re-aplicar 006: CREATE OR REPLACE VIEW conserva la ACL de la vista.
    SELECT array_agg(c.relname || '=' || COALESCE(c.relacl::text, '-')
                     ORDER BY c.relname)
      INTO v_acl_v
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = ANY (c_vistas);

    FOREACH r IN ARRAY c_vistas LOOP
        v_def := pg_get_viewdef(r::regclass);
        EXECUTE format('CREATE OR REPLACE VIEW %I AS %s', r, v_def);
    END LOOP;

    SELECT array_agg(c.relname || '=' || COALESCE(c.relacl::text, '-')
                     ORDER BY c.relname)
      INTO v_acl_v2
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = ANY (c_vistas);

    IF v_acl_v IS DISTINCT FROM v_acl_v2 THEN
        RAISE EXCEPTION 'FAIL: CREATE OR REPLACE VIEW perdió ACL (% vs %)', v_acl_v, v_acl_v2;
    END IF;

    IF NOT has_table_privilege('app_rw', 'vw_ficha_vino', 'SELECT')
       OR NOT has_table_privilege('reporte_ro', 'vw_ventas_mensuales_sala', 'SELECT') THEN
        RAISE EXCEPTION 'FAIL: re-aplicar 006 perdió los GRANT de las vistas';
    END IF;
    RAISE NOTICE 'OK (K2): re-aplicar 006 (CREATE OR REPLACE VIEW) preserva las ACL de las 4 vistas';
END $$;

-- -----------------------------------------------------------------------------
-- L. Privilegios por defecto de rutinas futuras.
--    El ALTER DEFAULT PRIVILEGES de la sección 8 de 007 debe cancelar el
--    EXECUTE implícito que PostgreSQL concede a PUBLIC en toda función nueva.
--    La ACL por defecto está ligada al rol que la declara, así que se prueban
--    los dos roles creadores reales: el runner de migraciones (el rol con el
--    que corre esta suite) y bda_owner, que tiene CREATE sobre public. Se
--    crean sondas bajo cada uno, se comprueba que PUBLIC, app_rw y reporte_ro
--    no pueden ejecutarlas y se eliminan al final. El DDL es transaccional: si
--    una aserción aborta, el CREATE también se revierte.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.t7_probe_default_exec();
DROP FUNCTION IF EXISTS public.t7_probe_default_bda();

CREATE FUNCTION public.t7_probe_default_exec() RETURNS integer
    LANGUAGE sql STABLE AS $$ SELECT 1 $$;

-- Se crea como bda_owner (no se cambia el OWNER después: ALTER OWNER no
-- re-aplica la ACL por defecto, y la prueba sería vacía). bda_owner tiene
-- CREATE sobre public y SET ROLE funciona aunque rolcanlogin sea false.
SET ROLE bda_owner;
CREATE FUNCTION public.t7_probe_default_bda() RETURNS integer
    LANGUAGE sql STABLE AS $$ SELECT 2 $$;
RESET ROLE;

DO $$
BEGIN
    IF has_function_privilege('public', 'public.t7_probe_default_exec()', 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: una rutina nueva del runner queda ejecutable por PUBLIC';
    END IF;

    IF has_function_privilege('app_rw', 'public.t7_probe_default_exec()', 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: una rutina nueva del runner queda ejecutable por app_rw';
    END IF;

    IF has_function_privilege('reporte_ro', 'public.t7_probe_default_exec()', 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: una rutina nueva del runner queda ejecutable por reporte_ro';
    END IF;

    IF has_function_privilege('public', 'public.t7_probe_default_bda()', 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: una rutina nueva de bda_owner queda ejecutable por PUBLIC';
    END IF;

    IF has_function_privilege('app_rw', 'public.t7_probe_default_bda()', 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: una rutina nueva de bda_owner queda ejecutable por app_rw';
    END IF;

    IF has_function_privilege('reporte_ro', 'public.t7_probe_default_bda()', 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: una rutina nueva de bda_owner queda ejecutable por reporte_ro';
    END IF;

    RAISE NOTICE 'OK (L): ninguna rutina nueva hereda EXECUTE de PUBLIC, ni del runner ni de bda_owner';
END $$;

DROP FUNCTION IF EXISTS public.t7_probe_default_exec();
DROP FUNCTION IF EXISTS public.t7_probe_default_bda();

ROLLBACK;
