-- =============================================================================
-- db/tests/db_tests.sql · TPI «Bodegas del Atuel»
-- Pruebas manuales de constraints y funciones (Tareas 2.1 / 2.2)
--
-- Ejecución sugerida:
--   psql -v ON_ERROR_STOP=1 -f db/tests/db_tests.sql
--
-- Formato:
--   * Casos válidos: bloque DO $$ ... $$ que inserta, verifica y limpia.
--   * Casos inválidos: bloque DO $$ ... $$ que espera el SQLSTATE de la regla.
--     Si la operación no falla, RAISE EXCEPTION aborta la prueba.
--
-- RAISE solo existe en PL/pgSQL: por eso todos los casos van dentro de DO $$.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Datos base mínimos para satisfacer las FK de las pruebas
-- -----------------------------------------------------------------------------
-- Se confirman con COMMIT porque los casos siguientes los referencian.
-- ON CONFLICT DO NOTHING permite ejecutar el script más de una vez.
BEGIN;
    INSERT INTO bodega (cuit, razon_social, domicilio)
    VALUES ('20123456789', 'Bodega Prueba', 'Calle Falsa 123')
    ON CONFLICT DO NOTHING;

    INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
    VALUES (1, '5500', 'San Rafael', 'Mendoza', 'Encargado Test')
    ON CONFLICT DO NOTHING;

    INSERT INTO finca (id_finca, nombre, superficie_hectareas, departamento, provincia)
    VALUES (1, 'Finca Prueba', 10.00, 'San Rafael', 'Mendoza')
    ON CONFLICT DO NOTHING;

    INSERT INTO cepa (id_cepa, nombre, tipo)
    VALUES (1, 'Malbec', 'tinta')
    ON CONFLICT DO NOTHING;

    INSERT INTO sala (id_sala, direccion, dia_cierre_semanal, id_localidad)
    VALUES (1, 'Sala Prueba', 1, 1)
    ON CONFLICT DO NOTHING;

    -- Cliente genérico (socio) para las pruebas que solo necesitan un cliente.
    INSERT INTO cliente (id_cliente, nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, descuento)
    VALUES (1, 'Cliente Prueba', 'socio', 'DNI', '30123456', 'Calle Cliente 1', 1, '2020-01-01', 10.00)
    ON CONFLICT DO NOTHING;

    -- Cliente dedicado al subtipo exportador: la FK compuesta (id_cliente, tipo)
    -- exige que el tipo del cliente sea exactamente 'exportador'.
    INSERT INTO cliente (id_cliente, nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, descuento)
    VALUES (2, 'Exportador Prueba', 'exportador', 'CUIT', '30712345678', 'Calle Exportador 1', 1, '2020-01-01', 5.00)
    ON CONFLICT DO NOTHING;

    INSERT INTO exportador (id_cliente, pais_destino_principal)
    VALUES (2, 'Chile')
    ON CONFLICT DO NOTHING;

    INSERT INTO transportista (id_transportista, razon_social, cuit, email, telefono, domicilio)
    VALUES (1, 'Transportista Prueba', '20987654321', 'test@test.com', '2621234567', 'Calle Transportista 1')
    ON CONFLICT DO NOTHING;
COMMIT;

-- -----------------------------------------------------------------------------
-- 1. CHECK: vino.graduacion BETWEEN 5 AND 20
-- -----------------------------------------------------------------------------
-- 1a. Debe funcionar: graduacion = 14 (dentro del rango)
DO $$
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Grad OK', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789');

    RAISE NOTICE 'OK: graduacion 14 aceptada';

    DELETE FROM vino WHERE nombre_comercial = 'Vino Grad OK';
END $$;

-- 1b. Debe fallar: graduacion = 25 (fuera de rango)  -- esperado: 23514
DO $$
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Grad Mal', 'tinto', 2020, 750, 25.00, 1000.00, '20123456789');

    RAISE EXCEPTION 'FAIL: graduacion 25 no deberia permitirse';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: graduacion 25 rechazada (23514)';
END $$;

-- -----------------------------------------------------------------------------
-- 2. CHECK: vino.precio_venta > 0
-- -----------------------------------------------------------------------------
-- 2a. Debe funcionar: precio positivo
DO $$
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Precio OK', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789');

    RAISE NOTICE 'OK: precio_venta 1000 aceptado';

    DELETE FROM vino WHERE nombre_comercial = 'Vino Precio OK';
END $$;

-- 2b. Debe fallar: precio_venta = 0  -- esperado: 23514
DO $$
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Precio Mal', 'tinto', 2020, 750, 14.00, 0.00, '20123456789');

    RAISE EXCEPTION 'FAIL: precio 0 no deberia permitirse';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: precio 0 rechazado (23514)';
END $$;

-- -----------------------------------------------------------------------------
-- 3. CHECK cruzado: permiso_exportacion.fecha_vencimiento > fecha_emision
-- -----------------------------------------------------------------------------
-- Usa el cliente exportador (id_cliente = 2), no el socio.
-- 3a. Debe funcionar: vencimiento posterior a emision
DO $$
BEGIN
    INSERT INTO permiso_exportacion (id_cliente, cod_permiso, fecha_emision, fecha_vencimiento)
    VALUES (2, 'PERM-001', '2024-01-01', '2025-01-01');

    RAISE NOTICE 'OK: vencimiento > emision aceptado';

    DELETE FROM permiso_exportacion WHERE id_cliente = 2 AND cod_permiso = 'PERM-001';
END $$;

-- 3b. Debe fallar: vencimiento anterior a emision  -- esperado: 23514
DO $$
BEGIN
    INSERT INTO permiso_exportacion (id_cliente, cod_permiso, fecha_emision, fecha_vencimiento)
    VALUES (2, 'PERM-002', '2025-01-01', '2024-01-01');

    RAISE EXCEPTION 'FAIL: vencimiento < emision no deberia permitirse';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: vencimiento < emision rechazado (23514)';
END $$;

-- -----------------------------------------------------------------------------
-- 4. CHECK cruzado: comprobante.total = subtotal - descuento
-- -----------------------------------------------------------------------------
-- 4a. Debe funcionar: total consistente
DO $$
DECLARE
    v_nro integer;
BEGIN
    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES ('2024-06-01', 1, 1, 1000.00, 100.00, 900.00)
    RETURNING nro_comprobante INTO v_nro;

    RAISE NOTICE 'OK: total = subtotal - descuento aceptado';

    DELETE FROM comprobante WHERE nro_comprobante = v_nro;
END $$;

-- 4b. Debe fallar: total inconsistente  -- esperado: 23514
DO $$
BEGIN
    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES ('2024-06-01', 1, 1, 1000.00, 100.00, 950.00);

    RAISE EXCEPTION 'FAIL: total inconsistente no deberia permitirse';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: total inconsistente rechazado (23514)';
END $$;

-- -----------------------------------------------------------------------------
-- 5. UNIQUE: vino (nombre_comercial, anada, presentacion_ml)
-- -----------------------------------------------------------------------------
-- 5a. Primera insercion valida (queda confirmada para que 5b choque)
DO $$
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Malbec Reserva', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'OK: vino unico insertado';
END $$;

-- 5b. Debe fallar: duplicado (mismo nombre, anada y presentacion)  -- esperado: 23505
DO $$
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Malbec Reserva', 'tinto', 2020, 750, 14.00, 1100.00, '20123456789');

    RAISE EXCEPTION 'FAIL: vino duplicado no deberia permitirse';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: vino duplicado rechazado (23505)';
END $$;

-- Limpieza del dato confirmado en 5a
DELETE FROM vino
WHERE nombre_comercial = 'Malbec Reserva' AND anada = 2020 AND presentacion_ml = 750;

-- -----------------------------------------------------------------------------
-- 6. UNIQUE: cliente (tipo_documento, nro_documento)
-- -----------------------------------------------------------------------------
-- 6a. Primera insercion valida (queda confirmada para que 6b choque)
DO $$
BEGIN
    INSERT INTO cliente (id_cliente, nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, descuento)
    VALUES (10, 'Cliente Unico Test', 'socio', 'DNI', '30999999', 'Otra Calle', 1, '2021-01-01', 5.00)
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'OK: cliente unico insertado';
END $$;

-- 6b. Debe fallar: mismo tipo_documento y nro_documento  -- esperado: 23505
DO $$
BEGIN
    INSERT INTO cliente (id_cliente, nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, descuento)
    VALUES (11, 'Cliente Duplicado Test', 'distribuidor', 'DNI', '30999999', 'Otra Calle 2', 1, '2021-02-01', 0.00);

    RAISE EXCEPTION 'FAIL: cliente duplicado no deberia permitirse';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: cliente duplicado rechazado (23505)';
END $$;

-- Limpieza del dato confirmado en 6a
DELETE FROM cliente WHERE tipo_documento = 'DNI' AND nro_documento = '30999999';

-- -----------------------------------------------------------------------------
-- 7. CHECK: stock_sala.cantidad >= 0
-- -----------------------------------------------------------------------------
-- 7a. Debe funcionar: cantidad = 0
DO $$
DECLARE
    v_cod integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Stock OK', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_cod;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, v_cod, 0);

    RAISE NOTICE 'OK: stock 0 aceptado';

    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_cod;
    DELETE FROM vino WHERE cod_vino = v_cod;
END $$;

-- 7b. Debe fallar: cantidad negativa  -- esperado: 23514
DO $$
DECLARE
    v_cod integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Stock Mal', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_cod;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, v_cod, -5);

    RAISE EXCEPTION 'FAIL: stock negativo no deberia permitirse';
EXCEPTION WHEN check_violation THEN
    -- El bloque se revierte completo: el vino insertado antes tampoco persiste.
    RAISE NOTICE 'OK: stock negativo rechazado (23514)';
END $$;

-- -----------------------------------------------------------------------------
-- 8. DEFAULT: ingreso.estado = 'en_confeccion'
-- -----------------------------------------------------------------------------
-- 8a. Debe funcionar: estado por defecto aplicado al crear ingreso
DO $$
DECLARE
    v_cod    integer;
    v_estado estado_documento;
BEGIN
    INSERT INTO ingreso (fecha, id_transportista, cuit_bodega)
    VALUES ('2024-06-01', 1, '20123456789')
    RETURNING cod_ingreso, estado INTO v_cod, v_estado;

    IF v_estado <> 'en_confeccion' THEN
        RAISE EXCEPTION 'FAIL: estado por defecto = % (esperado en_confeccion)', v_estado;
    END IF;

    RAISE NOTICE 'OK: ingreso creado con estado por defecto en_confeccion';

    DELETE FROM ingreso WHERE cod_ingreso = v_cod;
END $$;

-- -----------------------------------------------------------------------------
-- 9. CHECK: renglon_comprobante.descuento >= 0 (importe, no porcentaje)
-- -----------------------------------------------------------------------------
-- 9a. Debe funcionar: descuento = 150.00 (mayor a 100, pero es un importe)
DO $$
DECLARE
    v_cod integer;
    v_nro integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Descuento OK', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_cod;

    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES ('2024-06-01', 1, 1, 1000.00, 0.00, 1000.00)
    RETURNING nro_comprobante INTO v_nro;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
    VALUES (v_nro, v_cod, 1, 1000.00, 150.00, 850.00);

    RAISE NOTICE 'OK: descuento 150.00 aceptado como importe';

    DELETE FROM comprobante WHERE nro_comprobante = v_nro;
    DELETE FROM vino WHERE cod_vino = v_cod;
END $$;

-- 9b. Debe fallar: descuento = -1  -- esperado: 23514
DO $$
DECLARE
    v_cod integer;
    v_nro integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Descuento Mal', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_cod;

    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES ('2024-06-01', 1, 1, 1000.00, 0.00, 1000.00)
    RETURNING nro_comprobante INTO v_nro;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
    VALUES (v_nro, v_cod, 1, 1000.00, -1.00, 1001.00);

    RAISE EXCEPTION 'FAIL: descuento negativo no deberia permitirse';
EXCEPTION WHEN check_violation THEN
    -- El bloque se revierte completo: el vino y el comprobante tampoco persisten.
    RAISE NOTICE 'OK: descuento negativo rechazado (23514)';
END $$;

-- -----------------------------------------------------------------------------
-- 10. FK compuesta: cliente.tipo no se actualiza si existe fila de subtipo
-- -----------------------------------------------------------------------------
-- 10a. Debe fallar: el cliente 2 es exportador y tiene fila en exportador
DO $$
BEGIN
    UPDATE cliente SET tipo = 'socio' WHERE id_cliente = 2;

    RAISE EXCEPTION 'FAIL: cambio de tipo con exportador existente no deberia permitirse';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK: update de tipo bloqueado por FK (23503)';
END $$;

-- 10b. Debe funcionar: un cliente sin fila de subtipo puede cambiar de tipo
DO $$
DECLARE
    v_id integer;
BEGIN
    SELECT COALESCE(MAX(id_cliente), 0) + 1 INTO v_id FROM cliente;

    INSERT INTO cliente (id_cliente, nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, descuento)
    VALUES (v_id, 'Cliente Sin Subtipo', 'socio', 'DNI', '30888888', 'Calle Sin Subtipo 1', 1, '2020-01-01', 0.00);

    UPDATE cliente SET tipo = 'distribuidor' WHERE id_cliente = v_id;

    RAISE NOTICE 'OK: cliente sin subtipo puede cambiar de tipo';

    DELETE FROM cliente WHERE id_cliente = v_id;
END $$;

-- -----------------------------------------------------------------------------
-- 11. CHECK: localidad.codigo_postal con formato de 4 dígitos
-- -----------------------------------------------------------------------------
-- 11a. Debe funcionar: '5600'
DO $$
DECLARE
    v_id integer;
BEGIN
    SELECT COALESCE(MAX(id_localidad), 0) + 1 INTO v_id FROM localidad;

    INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
    VALUES (v_id, '5600', 'Localidad CP OK', 'Mendoza', 'Encargado Test');

    RAISE NOTICE 'OK: codigo postal 5600 aceptado';

    DELETE FROM localidad WHERE id_localidad = v_id;
END $$;

-- 11b. Debe fallar: '55'  -- esperado: 23514
DO $$
DECLARE
    v_id integer;
BEGIN
    SELECT COALESCE(MAX(id_localidad), 0) + 1 INTO v_id FROM localidad;

    INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
    VALUES (v_id, '55', 'Localidad CP Mal', 'Mendoza', 'Encargado Test');

    RAISE EXCEPTION 'FAIL: codigo postal invalido no deberia permitirse';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: codigo postal invalido rechazado (23514)';
END $$;

-- =============================================================================
-- Fin de pruebas 002_constraints.sql y 003_funciones.sql
-- Los datos base de la sección 0 quedan confirmados; usar una base de pruebas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 12. Funciones de 003_funciones.sql
-- -----------------------------------------------------------------------------
-- 12a. Descuentos RN-06: mapeo, STRICT y mensaje/SQLSTATE exactos.
DO $$
DECLARE
    v_message text;
    v_raised  boolean := false;
BEGIN
    IF fn_descuento_cliente('socio') <> 10.00::numeric
       OR fn_descuento_cliente('distribuidor') <> 20.00::numeric
       OR fn_descuento_cliente('exportador') <> 30.00::numeric THEN
        RAISE EXCEPTION 'FAIL: mapeo RN-06 incorrecto';
    END IF;

    IF fn_descuento_cliente(NULL::varchar) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: fn_descuento_cliente(NULL) debe devolver NULL';
    END IF;

    BEGIN
        PERFORM fn_descuento_cliente('desconocido');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> '[RN-06] Tipo de cliente desconocido: desconocido' THEN
            RAISE EXCEPTION 'FAIL: mensaje RN-06 inesperado: %', v_message;
        END IF;
        v_raised := true;
    END;

    IF NOT v_raised THEN
        RAISE EXCEPTION 'FAIL: tipo de cliente desconocido debe fallar con P0001';
    END IF;

    RAISE NOTICE 'OK: fn_descuento_cliente cumple RN-06';
END $$;

-- 12b. Stock: cantidad existente y 0 cuando falta la combinación sala/vino.
DO $$
DECLARE
    v_vino_con_stock integer;
    v_vino_sin_stock integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Fn Stock Con', 'tinto', 2022, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino_con_stock;

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Fn Stock Sin', 'tinto', 2022, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino_sin_stock;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    VALUES (1, v_vino_con_stock, 7);

    IF fn_stock_sala(1, v_vino_con_stock) <> 7 THEN
        RAISE EXCEPTION 'FAIL: fn_stock_sala no devolvio la cantidad almacenada';
    END IF;

    IF fn_stock_sala(1, v_vino_sin_stock) <> 0 THEN
        RAISE EXCEPTION 'FAIL: fn_stock_sala debe devolver 0 si no hay fila';
    END IF;

    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino_con_stock;
    DELETE FROM vino WHERE cod_vino IN (v_vino_con_stock, v_vino_sin_stock);

    RAISE NOTICE 'OK: fn_stock_sala cumple casos con y sin fila';
END $$;

-- 12c. Antigüedad: años completos, fechas futuras acotadas a 0 y STRICT.
DO $$
BEGIN
    IF fn_antiguedad_anios((CURRENT_DATE - INTERVAL '5 years')::date) <> 5
       OR fn_antiguedad_anios((CURRENT_DATE - INTERVAL '5 years 1 day')::date) <> 5
       OR fn_antiguedad_anios((CURRENT_DATE - INTERVAL '5 years 11 months')::date) <> 5 THEN
        RAISE EXCEPTION 'FAIL: fn_antiguedad_anios debe contar años completos';
    END IF;

    IF fn_antiguedad_anios(CURRENT_DATE + 1) <> 0 THEN
        RAISE EXCEPTION 'FAIL: fecha futura debe devolver 0';
    END IF;

    IF fn_antiguedad_anios(NULL::date) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: fn_antiguedad_anios(NULL) debe devolver NULL';
    END IF;

    RAISE NOTICE 'OK: fn_antiguedad_anios cumple años completos, futuro y STRICT';
END $$;

-- 12d. Totales: vacío, una línea, tres líneas y suma de importes redondeados.
DO $$
DECLARE
    v_vino_uno       integer;
    v_vino_redondeo1 integer;
    v_vino_redondeo2 integer;
    v_vino_redondeo3 integer;
    v_nro_vacio      integer;
    v_nro_uno        integer;
    v_nro_redondeo   integer;
    v_nro_inexistente integer;
    v_resultado      record;
    v_filas          bigint;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Fn Total Uno', 'tinto', 2022, 750, 14.00, 10.00, '20123456789')
    RETURNING cod_vino INTO v_vino_uno;

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Fn Total Redondeo 1', 'tinto', 2022, 750, 14.00, 0.33, '20123456789')
    RETURNING cod_vino INTO v_vino_redondeo1;

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Fn Total Redondeo 2', 'tinto', 2022, 750, 14.00, 0.33, '20123456789')
    RETURNING cod_vino INTO v_vino_redondeo2;

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Fn Total Redondeo 3', 'tinto', 2022, 750, 14.00, 0.33, '20123456789')
    RETURNING cod_vino INTO v_vino_redondeo3;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    VALUES
        (1, v_vino_uno, 10),
        (1, v_vino_redondeo1, 10),
        (1, v_vino_redondeo2, 10),
        (1, v_vino_redondeo3, 10);

    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES (CURRENT_DATE, 1, 1, 0.00, 0.00, 0.00)
    RETURNING nro_comprobante INTO v_nro_vacio;

    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES (CURRENT_DATE, 1, 1, 0.00, 0.00, 0.00)
    RETURNING nro_comprobante INTO v_nro_uno;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
    VALUES (v_nro_uno, v_vino_uno, 1, 10.00, 1.00, 9.00);

    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES (CURRENT_DATE, 1, 1, 0.00, 0.00, 0.00)
    RETURNING nro_comprobante INTO v_nro_redondeo;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
    VALUES
        (v_nro_redondeo, v_vino_redondeo1, 1, 0.33, 0.03, 0.30),
        (v_nro_redondeo, v_vino_redondeo2, 1, 0.33, 0.03, 0.30),
        (v_nro_redondeo, v_vino_redondeo3, 1, 0.33, 0.03, 0.30);

    SELECT count(*) INTO v_filas FROM fn_total_comprobante(v_nro_vacio);
    SELECT * INTO v_resultado FROM fn_total_comprobante(v_nro_vacio);
    IF v_filas <> 1 OR v_resultado.subtotal <> 0 OR v_resultado.descuento <> 0 OR v_resultado.total <> 0 THEN
        RAISE EXCEPTION 'FAIL: comprobante sin renglones debe devolver una fila (0, 0, 0)';
    END IF;

    SELECT count(*) INTO v_filas FROM fn_total_comprobante(NULL::integer);
    SELECT * INTO v_resultado FROM fn_total_comprobante(NULL::integer);
    IF v_filas <> 1 OR v_resultado.subtotal <> 0 OR v_resultado.descuento <> 0 OR v_resultado.total <> 0 THEN
        RAISE EXCEPTION 'FAIL: p_nro NULL debe devolver ceros';
    END IF;

    SELECT COALESCE(MAX(nro_comprobante), 0) + 1
    INTO v_nro_inexistente
    FROM comprobante;
    SELECT count(*) INTO v_filas FROM fn_total_comprobante(v_nro_inexistente);
    SELECT * INTO v_resultado FROM fn_total_comprobante(v_nro_inexistente);
    IF v_filas <> 1 OR v_resultado.subtotal <> 0 OR v_resultado.descuento <> 0 OR v_resultado.total <> 0 THEN
        RAISE EXCEPTION 'FAIL: comprobante inexistente debe devolver una fila (0, 0, 0)';
    END IF;

    SELECT * INTO v_resultado FROM fn_total_comprobante(v_nro_uno);
    IF v_resultado.subtotal <> 10.00 OR v_resultado.descuento <> 1.00 OR v_resultado.total <> 9.00 THEN
        RAISE EXCEPTION 'FAIL: total de comprobante con una línea incorrecto';
    END IF;

    SELECT * INTO v_resultado FROM fn_total_comprobante(v_nro_redondeo);
    IF v_resultado.subtotal <> 0.99 OR v_resultado.descuento <> 0.09 OR v_resultado.total <> 0.90 THEN
        RAISE EXCEPTION 'FAIL: redondeo por línea esperado subtotal=0.99, descuento=0.09, total=0.90';
    END IF;

    UPDATE comprobante
    SET subtotal = v_resultado.subtotal,
        descuento = v_resultado.descuento,
        total = v_resultado.total
    WHERE nro_comprobante = v_nro_redondeo;

    IF NOT EXISTS (
        SELECT 1
        FROM comprobante
        WHERE nro_comprobante = v_nro_redondeo
          AND total = subtotal - descuento
    ) THEN
        RAISE EXCEPTION 'FAIL: los tres totales deben satisfacer ck_comprobante_total';
    END IF;

    DELETE FROM comprobante WHERE nro_comprobante IN (v_nro_vacio, v_nro_uno, v_nro_redondeo);
    DELETE FROM stock_sala
    WHERE id_sala = 1
      AND cod_vino IN (v_vino_uno, v_vino_redondeo1, v_vino_redondeo2, v_vino_redondeo3);
    DELETE FROM vino WHERE cod_vino IN (v_vino_uno, v_vino_redondeo1, v_vino_redondeo2, v_vino_redondeo3);

    RAISE NOTICE 'OK: fn_total_comprobante cumple vacio, una línea y redondeo por línea';
END $$;

-- 12e. Verifica las propiedades declaradas en el catálogo de PostgreSQL.
DO $$
DECLARE
    v_volatilidad "char";
    v_estricta boolean;
    v_lenguaje name;
BEGIN
    SELECT p.provolatile, p.proisstrict, l.lanname
    INTO v_volatilidad, v_estricta, v_lenguaje
    FROM pg_proc AS p
    JOIN pg_language AS l ON l.oid = p.prolang
    WHERE p.oid = 'fn_descuento_cliente(varchar)'::regprocedure;
    IF NOT FOUND OR v_volatilidad <> 'i' OR NOT v_estricta OR v_lenguaje <> 'plpgsql' THEN
        RAISE EXCEPTION 'FAIL: atributos de fn_descuento_cliente incorrectos';
    END IF;

    SELECT p.provolatile, p.proisstrict, l.lanname
    INTO v_volatilidad, v_estricta, v_lenguaje
    FROM pg_proc AS p
    JOIN pg_language AS l ON l.oid = p.prolang
    WHERE p.oid = 'fn_stock_sala(integer,integer)'::regprocedure;
    IF NOT FOUND OR v_volatilidad <> 's' OR v_estricta OR v_lenguaje <> 'sql' THEN
        RAISE EXCEPTION 'FAIL: atributos de fn_stock_sala incorrectos';
    END IF;

    SELECT p.provolatile, p.proisstrict, l.lanname
    INTO v_volatilidad, v_estricta, v_lenguaje
    FROM pg_proc AS p
    JOIN pg_language AS l ON l.oid = p.prolang
    WHERE p.oid = 'fn_antiguedad_anios(date)'::regprocedure;
    IF NOT FOUND OR v_volatilidad <> 's' OR NOT v_estricta OR v_lenguaje <> 'sql' THEN
        RAISE EXCEPTION 'FAIL: atributos de fn_antiguedad_anios incorrectos';
    END IF;

    SELECT p.provolatile, p.proisstrict, l.lanname
    INTO v_volatilidad, v_estricta, v_lenguaje
    FROM pg_proc AS p
    JOIN pg_language AS l ON l.oid = p.prolang
    WHERE p.oid = 'fn_total_comprobante(integer)'::regprocedure;
    IF NOT FOUND OR v_volatilidad <> 's' OR v_estricta OR v_lenguaje <> 'sql' THEN
        RAISE EXCEPTION 'FAIL: atributos de fn_total_comprobante incorrectos';
    END IF;

    RAISE NOTICE 'OK: volatilidad, STRICT y lenguaje de las cuatro funciones';
END $$;
