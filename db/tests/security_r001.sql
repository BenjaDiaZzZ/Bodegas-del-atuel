-- =============================================================================
-- db/tests/security_r001.sql · TPI «Bodegas del Atuel»
-- Suite de seguridad del hallazgo R-001 (SECURITY DEFINER + matriz de app_rw).
--
-- Ejecucion (como owner):
--   psql -X -q -v ON_ERROR_STOP=1 -f db/tests/security_r001.sql
--
-- Requiere la base con las migraciones 001..007 aplicadas.
-- La suite es re-ejecutable: limpia al inicio y al final como owner, usa ids y
-- nombres unicos de prueba (9001 / 'Vino R001 Test') y no toca datos reales.
--
-- Formato:
--   * Casos negativos: se ejecutan como app_rw dentro de un DO que solo captura
--     insufficient_privilege (42501). Si la operacion no falla, RAISE EXCEPTION
--     aborta la suite (ON_ERROR_STOP).
--   * Casos funcionales: como app_rw, prueban que las rutinas DEFINER hacen el
--     trabajo aunque app_rw ya no tenga DML sobre las tablas criticas.
--   * Mensajes sin tildes ni caracteres especiales (convencion de contratos.md).
-- =============================================================================

-- =============================================================================
-- 0. Limpieza inicial como owner (deja la suite re-ejecutable)
-- =============================================================================
BEGIN;
    DELETE FROM auditoria_precio
     WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino R001 Test');
    DELETE FROM comprobante   WHERE id_cliente = 9001;
    DELETE FROM ingreso       WHERE id_transportista = 9001;
    DELETE FROM transferencia WHERE id_sala = 9001;
    DELETE FROM stock_sala    WHERE id_sala = 9001;
    DELETE FROM stock_deposito
     WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino R001 Test');
    DELETE FROM vino          WHERE nombre_comercial = 'Vino R001 Test';
    DELETE FROM sala          WHERE id_sala = 9001;
    DELETE FROM cliente       WHERE id_cliente = 9001;
    DELETE FROM transportista WHERE id_transportista = 9001;
    DELETE FROM localidad     WHERE id_localidad = 9001;
    DELETE FROM bodega        WHERE cuit = '27900123456';
COMMIT;

-- =============================================================================
-- 1. Setup como owner
-- =============================================================================
BEGIN;
    INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
    VALUES (9001, '5500', 'Localidad R001', 'Mendoza', 'Encargado R001');

    INSERT INTO bodega (cuit, razon_social, domicilio)
    VALUES ('27900123456', 'Bodega R001', 'Calle R001 1');

    INSERT INTO transportista (id_transportista, razon_social, cuit, email, telefono, domicilio)
    VALUES (9001, 'Transportista R001', '20900123456', 'r001@test.com', '2620000000', 'Calle R001 2');

    INSERT INTO sala (id_sala, direccion, dia_cierre_semanal, id_localidad)
    VALUES (9001, 'Sala R001', 1, 9001);

    INSERT INTO cliente (id_cliente, nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, descuento)
    VALUES (9001, 'Cliente R001', 'socio', 'DNI', '99001122', 'Calle R001 3', 9001, '2020-01-01', 10.00);

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino R001 Test', 'tinto', 2024, 750, 13.50, 1000.00, '27900123456');

    INSERT INTO stock_deposito (cod_vino, cantidad)
    SELECT cod_vino, 100 FROM vino WHERE nombre_comercial = 'Vino R001 Test';

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    SELECT 9001, cod_vino, 100 FROM vino WHERE nombre_comercial = 'Vino R001 Test';
COMMIT;

-- =============================================================================
-- 2. Casos negativos como app_rw (esperado 42501 insufficient_privilege)
-- =============================================================================
SET ROLE app_rw;

-- 2.1 UPDATE comprobante.total -- esperado: 42501
DO $$
BEGIN
    UPDATE comprobante SET total = 0 WHERE nro_comprobante = -1;
    RAISE EXCEPTION 'FAIL: app_rw pudo actualizar comprobante.total';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: UPDATE comprobante.total rechazado (42501)';
END $$;

-- 2.2 UPDATE stock_sala -- esperado: 42501
DO $$
BEGIN
    UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 9001;
    RAISE EXCEPTION 'FAIL: app_rw pudo actualizar stock_sala';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: UPDATE stock_sala rechazado (42501)';
END $$;

-- 2.3 INSERT stock_sala -- esperado: 42501
DO $$
BEGIN
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    VALUES (9001, -1, 1);
    RAISE EXCEPTION 'FAIL: app_rw pudo insertar en stock_sala';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: INSERT stock_sala rechazado (42501)';
END $$;

-- 2.4 DELETE stock_sala -- esperado: 42501
DO $$
BEGIN
    DELETE FROM stock_sala WHERE id_sala = 9001;
    RAISE EXCEPTION 'FAIL: app_rw pudo borrar de stock_sala';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: DELETE stock_sala rechazado (42501)';
END $$;

-- 2.5 UPDATE stock_deposito -- esperado: 42501
DO $$
BEGIN
    UPDATE stock_deposito SET cantidad = 0 WHERE cod_vino = -1;
    RAISE EXCEPTION 'FAIL: app_rw pudo actualizar stock_deposito';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: UPDATE stock_deposito rechazado (42501)';
END $$;

-- 2.6 INSERT stock_deposito -- esperado: 42501
DO $$
BEGIN
    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (-1, 1);
    RAISE EXCEPTION 'FAIL: app_rw pudo insertar en stock_deposito';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: INSERT stock_deposito rechazado (42501)';
END $$;

-- 2.7 DELETE stock_deposito -- esperado: 42501
DO $$
BEGIN
    DELETE FROM stock_deposito WHERE cod_vino = -1;
    RAISE EXCEPTION 'FAIL: app_rw pudo borrar de stock_deposito';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: DELETE stock_deposito rechazado (42501)';
END $$;

-- 2.8 UPDATE renglon_comprobante -- esperado: 42501
DO $$
BEGIN
    UPDATE renglon_comprobante SET cantidad = 1 WHERE nro_comprobante = -1;
    RAISE EXCEPTION 'FAIL: app_rw pudo actualizar renglon_comprobante';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: UPDATE renglon_comprobante rechazado (42501)';
END $$;

-- 2.9 DELETE renglon_comprobante -- esperado: 42501
DO $$
BEGIN
    DELETE FROM renglon_comprobante WHERE nro_comprobante = -1;
    RAISE EXCEPTION 'FAIL: app_rw pudo borrar renglon_comprobante';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: DELETE renglon_comprobante rechazado (42501)';
END $$;

-- 2.10 INSERT comprobante con columna calculada (subtotal) -- esperado: 42501
DO $$
BEGIN
    INSERT INTO comprobante (id_cliente, id_sala, subtotal)
    VALUES (9001, 9001, 0);
    RAISE EXCEPTION 'FAIL: app_rw pudo insertar comprobante.subtotal';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: INSERT comprobante.subtotal rechazado (42501)';
END $$;

-- 2.11 UPDATE ingreso.fecha -- esperado: 42501
DO $$
BEGIN
    UPDATE ingreso SET fecha = CURRENT_DATE WHERE cod_ingreso = -1;
    RAISE EXCEPTION 'FAIL: app_rw pudo actualizar ingreso.fecha';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: UPDATE ingreso.fecha rechazado (42501)';
END $$;

-- 2.12 UPDATE transferencia.fecha_confeccion -- esperado: 42501
DO $$
BEGIN
    UPDATE transferencia SET fecha_confeccion = CURRENT_DATE WHERE nro_solicitud = -1;
    RAISE EXCEPTION 'FAIL: app_rw pudo actualizar transferencia.fecha_confeccion';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: UPDATE transferencia.fecha_confeccion rechazado (42501)';
END $$;

-- 2.13 INSERT auditoria_precio -- esperado: 42501
DO $$
BEGIN
    INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo, usuario)
    VALUES ((SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino R001 Test'), 1.00, 2.00, 'intruso');
    RAISE EXCEPTION 'FAIL: app_rw pudo insertar en auditoria_precio';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: INSERT auditoria_precio rechazado (42501)';
END $$;

-- 2.14 DELETE comprobante -- esperado: 42501
DO $$
BEGIN
    DELETE FROM comprobante WHERE nro_comprobante = -1;
    RAISE EXCEPTION 'FAIL: app_rw pudo borrar comprobante';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: DELETE comprobante rechazado (42501)';
END $$;

-- 2.15 INSERT comprobante con descuento -- esperado: 42501
DO $$
BEGIN
    INSERT INTO comprobante (id_cliente, id_sala, descuento)
    VALUES (9001, 9001, 0);
    RAISE EXCEPTION 'FAIL: app_rw pudo insertar comprobante.descuento';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: INSERT comprobante.descuento rechazado (42501)';
END $$;

-- 2.16 INSERT comprobante con total -- esperado: 42501
DO $$
BEGIN
    INSERT INTO comprobante (id_cliente, id_sala, total)
    VALUES (9001, 9001, 0);
    RAISE EXCEPTION 'FAIL: app_rw pudo insertar comprobante.total';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: INSERT comprobante.total rechazado (42501)';
END $$;

RESET ROLE;

-- =============================================================================
-- 3. Casos funcionales como app_rw (las rutinas DEFINER hacen el trabajo)
-- =============================================================================
SET ROLE app_rw;

-- 3.1 Venta: T1 completa precio/descuento/subtotal y T2 descuenta stock y
--     recalcula la cabecera. Precio 1000, cliente socio (10 %), cantidad 5.
DO $$
DECLARE
    v_cod integer;
    v_nro integer;
    v_rc  renglon_comprobante%ROWTYPE;
BEGIN
    SELECT cod_vino INTO v_cod FROM vino WHERE nombre_comercial = 'Vino R001 Test';

    INSERT INTO comprobante (id_cliente, id_sala)
    VALUES (9001, 9001)
    RETURNING nro_comprobante INTO v_nro;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_nro, v_cod, 5);

    SELECT * INTO v_rc
      FROM renglon_comprobante
     WHERE nro_comprobante = v_nro
       AND cod_vino = v_cod;

    IF v_rc.precio_unitario <> 1000.00 OR v_rc.descuento <> 500.00 OR v_rc.subtotal <> 4500.00 THEN
        RAISE EXCEPTION 'FAIL: T1 no completo el renglon (precio %, descuento %, subtotal %)',
            v_rc.precio_unitario, v_rc.descuento, v_rc.subtotal;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM comprobante
         WHERE nro_comprobante = v_nro
           AND subtotal = 5000.00
           AND descuento = 500.00
           AND total = 4500.00
    ) THEN
        RAISE EXCEPTION 'FAIL: T2 no recalculo los totales de la cabecera';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM stock_sala
         WHERE id_sala = 9001
           AND cod_vino = v_cod
           AND cantidad = 95
    ) THEN
        RAISE EXCEPTION 'FAIL: T2 no desconto stock_sala (esperado 95)';
    END IF;

    RAISE NOTICE 'OK: venta completa renglon, totales y stock_sala (95)';
END $$;

-- 3.2 Ingreso: la API lo crea, lo termina y CALL sp_procesar_ingreso suma
--     stock_deposito y lo deja procesado. Deposito 100 + 20 = 120.
DO $$
DECLARE
    v_cod integer;
    v_ing integer;
BEGIN
    SELECT cod_vino INTO v_cod FROM vino WHERE nombre_comercial = 'Vino R001 Test';

    INSERT INTO ingreso (id_transportista, cuit_bodega)
    VALUES (9001, '27900123456')
    RETURNING cod_ingreso INTO v_ing;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_ing, v_cod, 20);

    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ing;

    CALL sp_procesar_ingreso(v_ing);

    IF NOT EXISTS (
        SELECT 1 FROM ingreso
         WHERE cod_ingreso = v_ing
           AND estado = 'procesado'
    ) THEN
        RAISE EXCEPTION 'FAIL: sp_procesar_ingreso no dejo el ingreso procesado';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM stock_deposito
         WHERE cod_vino = v_cod
           AND cantidad = 120
    ) THEN
        RAISE EXCEPTION 'FAIL: sp_procesar_ingreso no sumo stock_deposito (esperado 120)';
    END IF;

    RAISE NOTICE 'OK: sp_procesar_ingreso suma stock_deposito (120) y deja procesado';
END $$;

-- 3.3 Transferencia: la API la crea, la termina y CALL
--     sp_procesar_transferencia mueve deposito a sala y la deja procesada.
--     Deposito 120 - 10 = 110; sala 95 + 10 = 105.
DO $$
DECLARE
    v_cod integer;
    v_tr  integer;
BEGIN
    SELECT cod_vino INTO v_cod FROM vino WHERE nombre_comercial = 'Vino R001 Test';

    INSERT INTO transferencia (id_sala)
    VALUES (9001)
    RETURNING nro_solicitud INTO v_tr;

    INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
    VALUES (v_tr, v_cod, 10);

    UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = v_tr;

    CALL sp_procesar_transferencia(v_tr);

    IF NOT EXISTS (
        SELECT 1 FROM transferencia
         WHERE nro_solicitud = v_tr
           AND estado = 'procesado'
    ) THEN
        RAISE EXCEPTION 'FAIL: sp_procesar_transferencia no dejo la transferencia procesada';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM stock_deposito
         WHERE cod_vino = v_cod
           AND cantidad = 110
    ) THEN
        RAISE EXCEPTION 'FAIL: sp_procesar_transferencia no desconto stock_deposito (esperado 110)';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM stock_sala
         WHERE id_sala = 9001
           AND cod_vino = v_cod
           AND cantidad = 105
    ) THEN
        RAISE EXCEPTION 'FAIL: sp_procesar_transferencia no sumo stock_sala (esperado 105)';
    END IF;

    RAISE NOTICE 'OK: sp_procesar_transferencia mueve stock (deposito 110, sala 105) y deja procesado';
END $$;

RESET ROLE;

-- 3.4 Auditoria de precio (T7): sin app.usuario, el trigger DEFINER registra
--     session_user. Se usa SET SESSION AUTHORIZATION app_rw para que el valor
--     observable sea realmente 'app_rw' (con SET ROLE, session_user sigue
--     siendo el login owner; dentro de DEFINER current_user tambien es owner).
SET SESSION AUTHORIZATION app_rw;
DO $$
BEGIN
    UPDATE vino SET precio_venta = 1234.56 WHERE nombre_comercial = 'Vino R001 Test';

    IF NOT EXISTS (
        SELECT 1
          FROM auditoria_precio a
          JOIN vino v ON v.cod_vino = a.cod_vino
         WHERE v.nombre_comercial = 'Vino R001 Test'
           AND a.precio_anterior = 1000.00
           AND a.precio_nuevo = 1234.56
           AND a.usuario = 'app_rw'
    ) THEN
        RAISE EXCEPTION 'FAIL: T7 no registro session_user app_rw en auditoria_precio';
    END IF;

    RAISE NOTICE 'OK: UPDATE vino de app_rw audita usuario = app_rw (session_user)';
END $$;
RESET SESSION AUTHORIZATION;

-- 3.5 Precedencia de app.usuario sobre session_user (T7 DEFINER). Con
--     app.usuario seteado, la auditoria registra ese valor aunque el rol de
--     sesion sea app_rw. Parte del precio 1234.56 que dejo el caso 3.4.
SET SESSION AUTHORIZATION app_rw;
SET app.usuario = 'api-user-99';
DO $$
BEGIN
    UPDATE vino SET precio_venta = 1300.00 WHERE nombre_comercial = 'Vino R001 Test';

    IF NOT EXISTS (
        SELECT 1
          FROM auditoria_precio a
          JOIN vino v ON v.cod_vino = a.cod_vino
         WHERE v.nombre_comercial = 'Vino R001 Test'
           AND a.precio_anterior = 1234.56
           AND a.precio_nuevo = 1300.00
           AND a.usuario = 'api-user-99'
    ) THEN
        RAISE EXCEPTION 'FAIL: T7 no respeto la precedencia de app.usuario sobre session_user';
    END IF;

    RAISE NOTICE 'OK: UPDATE vino audita app.usuario = api-user-99 (precedencia)';
END $$;
RESET app.usuario;
RESET SESSION AUTHORIZATION;

-- 3.6 Invariante de datos: aunque app_rw dispare los triggers, los comandos
--     directos sobre columnas calculadas y sobre la cabecera se rechazan con
--     42501 y no alteran ninguna fila. Se compara un hash de comprobante y de
--     stock_sala antes y despues de los tres intentos.
SET ROLE app_rw;
DO $$
DECLARE
    v_cod        integer;
    v_nro        integer;
    v_hash_comp  text;
    v_hash_stock text;
BEGIN
    SELECT cod_vino INTO v_cod FROM vino WHERE nombre_comercial = 'Vino R001 Test';

    INSERT INTO comprobante (id_cliente, id_sala)
    VALUES (9001, 9001)
    RETURNING nro_comprobante INTO v_nro;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_nro, v_cod, 1);

    SELECT md5(cb::text) INTO v_hash_comp
      FROM comprobante cb WHERE nro_comprobante = v_nro;
    SELECT md5(ss::text) INTO v_hash_stock
      FROM stock_sala ss WHERE id_sala = 9001 AND cod_vino = v_cod;

    BEGIN
        UPDATE comprobante SET total = 0 WHERE nro_comprobante = v_nro;
        RAISE EXCEPTION 'FAIL: app_rw pudo actualizar comprobante.total';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: invariante - UPDATE comprobante.total rechazado (42501)';
    END;

    BEGIN
        DELETE FROM comprobante WHERE nro_comprobante = v_nro;
        RAISE EXCEPTION 'FAIL: app_rw pudo borrar comprobante';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: invariante - DELETE comprobante rechazado (42501)';
    END;

    BEGIN
        INSERT INTO comprobante (id_cliente, id_sala, total)
        VALUES (9001, 9001, 0);
        RAISE EXCEPTION 'FAIL: app_rw pudo insertar comprobante.total';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: invariante - INSERT comprobante.total rechazado (42501)';
    END;

    IF (SELECT md5(cb::text) FROM comprobante cb WHERE nro_comprobante = v_nro)
       IS DISTINCT FROM v_hash_comp THEN
        RAISE EXCEPTION 'FAIL: el comprobante cambio tras comandos rechazados';
    END IF;

    IF (SELECT md5(ss::text) FROM stock_sala ss WHERE id_sala = 9001 AND cod_vino = v_cod)
       IS DISTINCT FROM v_hash_stock THEN
        RAISE EXCEPTION 'FAIL: stock_sala cambio tras comandos rechazados';
    END IF;

    RAISE NOTICE 'OK: invariante intacto (comprobante y stock_sala sin cambios)';
END $$;
RESET ROLE;

-- =============================================================================
-- 4. Limpieza final como owner
-- =============================================================================
BEGIN;
    DELETE FROM auditoria_precio
     WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino R001 Test');
    DELETE FROM comprobante   WHERE id_cliente = 9001;
    DELETE FROM ingreso       WHERE id_transportista = 9001;
    DELETE FROM transferencia WHERE id_sala = 9001;
    DELETE FROM stock_sala    WHERE id_sala = 9001;
    DELETE FROM stock_deposito
     WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino R001 Test');
    DELETE FROM vino          WHERE nombre_comercial = 'Vino R001 Test';
    DELETE FROM sala          WHERE id_sala = 9001;
    DELETE FROM cliente       WHERE id_cliente = 9001;
    DELETE FROM transportista WHERE id_transportista = 9001;
    DELETE FROM localidad     WHERE id_localidad = 9001;
    DELETE FROM bodega        WHERE cuit = '27900123456';
COMMIT;
