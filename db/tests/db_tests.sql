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
-- El trigger BEFORE de 005 completa la linea en el INSERT; el limite del CHECK
-- se ejercita con un UPDATE posterior (no hay trigger de UPDATE sobre renglones).
DO $$
DECLARE
    v_cod integer;
    v_nro integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Descuento OK', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_cod;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, v_cod, 10);

    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES ('2024-06-01', 1, 1, 1000.00, 0.00, 1000.00)
    RETURNING nro_comprobante INTO v_nro;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_nro, v_cod, 1);

    UPDATE renglon_comprobante
       SET descuento = 150.00, subtotal = 850.00
     WHERE nro_comprobante = v_nro AND cod_vino = v_cod;

    RAISE NOTICE 'OK: descuento 150.00 aceptado como importe';

    DELETE FROM comprobante WHERE nro_comprobante = v_nro;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_cod;
    DELETE FROM vino WHERE cod_vino = v_cod;
END $$;

-- 9b. Debe fallar: descuento = -1  -- esperado: 23514
-- El INSERT lo completa el trigger de 005; el CHECK se prueba con un UPDATE.
DO $$
DECLARE
    v_cod integer;
    v_nro integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('Vino Descuento Mal', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_cod;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, v_cod, 10);

    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES ('2024-06-01', 1, 1, 1000.00, 0.00, 1000.00)
    RETURNING nro_comprobante INTO v_nro;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_nro, v_cod, 1);

    BEGIN
        UPDATE renglon_comprobante
           SET descuento = -1.00
         WHERE nro_comprobante = v_nro AND cod_vino = v_cod;

        RAISE EXCEPTION 'FAIL: descuento negativo no deberia permitirse';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: descuento negativo rechazado (23514)';
    END;

    DELETE FROM comprobante WHERE nro_comprobante = v_nro;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_cod;
    DELETE FROM vino WHERE cod_vino = v_cod;
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

-- -----------------------------------------------------------------------------
-- 13. Procedimientos de 004_procedimientos.sql (RN-10 y RN-11)
-- -----------------------------------------------------------------------------
-- Cada caso monta sus propios datos y los limpia al final. Para los casos de
-- error se usa un bloque BEGIN ... EXCEPTION anidado: al capturar la excepción
-- se revierte SOLO el bloque anidado, así el montaje del bloque externo queda
-- intacto y se puede comprobar que el documento y los stocks no cambiaron.
-- Las comparaciones usan IS DISTINCT FROM para no pasar por alto valores NULL.

-- 13a. Ingreso válido: suma stock, crea la fila ausente y pasa a procesado.
DO $$
DECLARE
    v_vino_a integer;
    v_vino_b integer;
    v_cod    integer;
    v_estado estado_documento;
    v_dep_a  integer;
    v_dep_b  integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Ing A', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino_a;

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Ing B', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino_b;

    INSERT INTO ingreso (fecha, id_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 1, '20123456789')
    RETURNING cod_ingreso INTO v_cod;

    -- RN-12: los renglones se cargan con el documento en en_confeccion.
    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_cod, v_vino_a, 5), (v_cod, v_vino_b, 3);

    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_cod;

    -- vino_a con stock previo; vino_b sin fila: el upsert debe crearla.
    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino_a, 10);

    CALL sp_procesar_ingreso(v_cod);

    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = v_cod;
    SELECT cantidad INTO v_dep_a FROM stock_deposito WHERE cod_vino = v_vino_a;
    SELECT cantidad INTO v_dep_b FROM stock_deposito WHERE cod_vino = v_vino_b;

    IF v_estado IS DISTINCT FROM 'procesado' THEN
        RAISE EXCEPTION 'FAIL: ingreso no quedo procesado (estado=%)', v_estado;
    END IF;
    IF v_dep_a IS DISTINCT FROM 15 OR v_dep_b IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'FAIL: stock del deposito incorrecto (a=%, b=%)', v_dep_a, v_dep_b;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_ingreso suma stock (crea fila ausente) y pasa a procesado';

    DELETE FROM ingreso WHERE cod_ingreso = v_cod;
    DELETE FROM stock_deposito WHERE cod_vino IN (v_vino_a, v_vino_b);
    DELETE FROM vino WHERE cod_vino IN (v_vino_a, v_vino_b);
END $$;

-- 13b. Ingreso no terminado: P0001 y nada cambia.
DO $$
DECLARE
    v_vino   integer;
    v_cod    integer;
    v_estado estado_documento;
    v_dep    integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Ing Mal', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO ingreso (fecha, id_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 1, '20123456789')
    RETURNING cod_ingreso INTO v_cod;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (v_cod, v_vino, 4);
    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino, 10);

    BEGIN
        CALL sp_procesar_ingreso(v_cod);
        RAISE EXCEPTION 'FAIL: un ingreso en_confeccion no deberia procesarse';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;

    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = v_cod;
    SELECT cantidad INTO v_dep FROM stock_deposito WHERE cod_vino = v_vino;
    IF v_estado IS DISTINCT FROM 'en_confeccion' OR v_dep IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'FAIL: estado/stock cambiaron (estado=%, dep=%)', v_estado, v_dep;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_ingreso rechaza estado no terminado (P0001)';

    DELETE FROM ingreso WHERE cod_ingreso = v_cod;
    DELETE FROM stock_deposito WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 13c. Ingreso repetido: el segundo CALL falla y no duplica el stock.
DO $$
DECLARE
    v_vino integer;
    v_cod  integer;
    v_dep  integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Ing Rep', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO ingreso (fecha, id_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 1, '20123456789')
    RETURNING cod_ingreso INTO v_cod;

    -- RN-12: el renglon se carga antes de pasar a terminado.
    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (v_cod, v_vino, 6);
    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_cod;

    CALL sp_procesar_ingreso(v_cod);

    BEGIN
        CALL sp_procesar_ingreso(v_cod);
        RAISE EXCEPTION 'FAIL: reprocesar un ingreso no deberia permitirse';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;

    SELECT cantidad INTO v_dep FROM stock_deposito WHERE cod_vino = v_vino;
    IF v_dep IS DISTINCT FROM 6 THEN
        RAISE EXCEPTION 'FAIL: el stock se duplico al reprocesar (dep=%)', v_dep;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_ingreso no reprocesa (P0001, stock intacto)';

    DELETE FROM ingreso WHERE cod_ingreso = v_cod;
    DELETE FROM stock_deposito WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 13d. Ingreso inexistente: P0002 (mapeado a 404 en docs/contratos.md).
DO $$
DECLARE
    v_inexistente integer;
BEGIN
    SELECT COALESCE(MAX(cod_ingreso), 0) + 1 INTO v_inexistente FROM ingreso;

    BEGIN
        CALL sp_procesar_ingreso(v_inexistente);
        RAISE EXCEPTION 'FAIL: un ingreso inexistente no deberia procesarse';
    EXCEPTION WHEN SQLSTATE 'P0002' THEN
        NULL;
    END;

    RAISE NOTICE 'OK: sp_procesar_ingreso inexistente devuelve P0002';
END $$;

-- 13e. Transferencia válida: descuenta depósito, acredita sala y procesa.
DO $$
DECLARE
    v_vino   integer;
    v_nro    integer;
    v_estado estado_documento;
    v_dep    integer;
    v_sala   integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Tr OK', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino, 100);

    -- D2: el INSERT solo acepta en_confeccion; el renglon se carga antes de
    -- pasar a terminado (RN-12).
    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (1, CURRENT_DATE)
    RETURNING nro_solicitud INTO v_nro;

    INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad) VALUES (v_nro, v_vino, 30);
    UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = v_nro;

    CALL sp_procesar_transferencia(v_nro);

    SELECT estado INTO v_estado FROM transferencia WHERE nro_solicitud = v_nro;
    SELECT cantidad INTO v_dep FROM stock_deposito WHERE cod_vino = v_vino;
    SELECT cantidad INTO v_sala FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;

    IF v_estado IS DISTINCT FROM 'procesado'
       OR v_dep IS DISTINCT FROM 70
       OR v_sala IS DISTINCT FROM 30 THEN
        RAISE EXCEPTION 'FAIL: transferencia valida (estado=%, dep=%, sala=%)', v_estado, v_dep, v_sala;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_transferencia descuenta deposito y acredita sala';

    DELETE FROM transferencia WHERE nro_solicitud = v_nro;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    DELETE FROM stock_deposito WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 13f. Transferencia no terminada: P0001 y nada cambia.
DO $$
DECLARE
    v_vino   integer;
    v_nro    integer;
    v_estado estado_documento;
    v_dep    integer;
    v_cnt    bigint;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Tr Mal', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino, 100);

    INSERT INTO transferencia (id_sala, fecha_confeccion, estado)
    VALUES (1, CURRENT_DATE, 'en_confeccion')
    RETURNING nro_solicitud INTO v_nro;

    INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad) VALUES (v_nro, v_vino, 30);

    BEGIN
        CALL sp_procesar_transferencia(v_nro);
        RAISE EXCEPTION 'FAIL: una transferencia en_confeccion no deberia procesarse';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;

    SELECT estado INTO v_estado FROM transferencia WHERE nro_solicitud = v_nro;
    SELECT cantidad INTO v_dep FROM stock_deposito WHERE cod_vino = v_vino;
    SELECT count(*) INTO v_cnt FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    IF v_estado IS DISTINCT FROM 'en_confeccion' OR v_dep IS DISTINCT FROM 100 OR v_cnt <> 0 THEN
        RAISE EXCEPTION 'FAIL: estado/stock cambiaron (estado=%, dep=%, sala=%)', v_estado, v_dep, v_cnt;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_transferencia rechaza estado no terminado (P0001)';

    DELETE FROM transferencia WHERE nro_solicitud = v_nro;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    DELETE FROM stock_deposito WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 13g. Transferencia repetida: el segundo CALL falla y no duplica el stock.
DO $$
DECLARE
    v_vino integer;
    v_nro  integer;
    v_dep  integer;
    v_sala integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Tr Rep', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino, 100);

    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (1, CURRENT_DATE)
    RETURNING nro_solicitud INTO v_nro;

    INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad) VALUES (v_nro, v_vino, 40);
    UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = v_nro;

    CALL sp_procesar_transferencia(v_nro);

    BEGIN
        CALL sp_procesar_transferencia(v_nro);
        RAISE EXCEPTION 'FAIL: reprocesar una transferencia no deberia permitirse';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;

    SELECT cantidad INTO v_dep FROM stock_deposito WHERE cod_vino = v_vino;
    SELECT cantidad INTO v_sala FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    IF v_dep IS DISTINCT FROM 60 OR v_sala IS DISTINCT FROM 40 THEN
        RAISE EXCEPTION 'FAIL: el stock se duplico al reprocesar (dep=%, sala=%)', v_dep, v_sala;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_transferencia no reprocesa (P0001, stock intacto)';

    DELETE FROM transferencia WHERE nro_solicitud = v_nro;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    DELETE FROM stock_deposito WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 13h. Transferencia con vino sin fila de stock en el depósito: P0001, sin cambios.
DO $$
DECLARE
    v_vino   integer;
    v_nro    integer;
    v_estado estado_documento;
    v_cnt_dep bigint;
    v_cnt_sala bigint;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Tr Sin', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    -- Sin fila en stock_deposito: la transferencia no debe asumir 0.
    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (1, CURRENT_DATE)
    RETURNING nro_solicitud INTO v_nro;

    INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad) VALUES (v_nro, v_vino, 10);
    UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = v_nro;

    BEGIN
        CALL sp_procesar_transferencia(v_nro);
        RAISE EXCEPTION 'FAIL: transferencia sin fila de deposito no deberia procesarse';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;

    SELECT estado INTO v_estado FROM transferencia WHERE nro_solicitud = v_nro;
    SELECT count(*) INTO v_cnt_dep FROM stock_deposito WHERE cod_vino = v_vino;
    SELECT count(*) INTO v_cnt_sala FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    IF v_estado IS DISTINCT FROM 'terminado' OR v_cnt_dep <> 0 OR v_cnt_sala <> 0 THEN
        RAISE EXCEPTION 'FAIL: estado/stocks cambiaron (estado=%, dep=%, sala=%)', v_estado, v_cnt_dep, v_cnt_sala;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_transferencia rechaza vino sin fila de deposito (P0001)';

    DELETE FROM transferencia WHERE nro_solicitud = v_nro;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    DELETE FROM stock_deposito WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 13i. Transferencia con stock insuficiente: P0001, sin cambios.
DO $$
DECLARE
    v_vino   integer;
    v_nro    integer;
    v_estado estado_documento;
    v_dep    integer;
    v_cnt_sala bigint;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Tr Ins', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino, 5);

    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (1, CURRENT_DATE)
    RETURNING nro_solicitud INTO v_nro;

    INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad) VALUES (v_nro, v_vino, 10);
    UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = v_nro;

    BEGIN
        CALL sp_procesar_transferencia(v_nro);
        RAISE EXCEPTION 'FAIL: transferencia con stock insuficiente no deberia procesarse';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;

    SELECT estado INTO v_estado FROM transferencia WHERE nro_solicitud = v_nro;
    SELECT cantidad INTO v_dep FROM stock_deposito WHERE cod_vino = v_vino;
    SELECT count(*) INTO v_cnt_sala FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    IF v_estado IS DISTINCT FROM 'terminado' OR v_dep IS DISTINCT FROM 5 OR v_cnt_sala <> 0 THEN
        RAISE EXCEPTION 'FAIL: estado/stocks cambiaron (estado=%, dep=%, sala=%)', v_estado, v_dep, v_cnt_sala;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_transferencia rechaza stock insuficiente (P0001)';

    DELETE FROM transferencia WHERE nro_solicitud = v_nro;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    DELETE FROM stock_deposito WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 13j. Multirrenglón con falla: si un vino no tiene stock, NINGÚN vino cambia
--      (documento y ambas tablas de stock byte a byte iguales al arranque).
DO $$
DECLARE
    v_vino_a integer;
    v_vino_b integer;
    v_vino_c integer;
    v_nro    integer;
    v_estado estado_documento;
    v_dep_a  integer;
    v_dep_c  integer;
    v_cnt_b  bigint;
    v_cnt_sala bigint;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Tr Mr A', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino_a;

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Tr Mr B', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino_b;

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('JD004 Tr Mr C', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino_c;

    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino_a, 50), (v_vino_c, 50);

    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (1, CURRENT_DATE)
    RETURNING nro_solicitud INTO v_nro;

    INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
    VALUES (v_nro, v_vino_a, 10), (v_nro, v_vino_b, 10), (v_nro, v_vino_c, 10);

    UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = v_nro;

    BEGIN
        CALL sp_procesar_transferencia(v_nro);
        RAISE EXCEPTION 'FAIL: la transferencia multirrenglon debia fallar por el vino B';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;

    SELECT estado INTO v_estado FROM transferencia WHERE nro_solicitud = v_nro;
    SELECT cantidad INTO v_dep_a FROM stock_deposito WHERE cod_vino = v_vino_a;
    SELECT cantidad INTO v_dep_c FROM stock_deposito WHERE cod_vino = v_vino_c;
    SELECT count(*) INTO v_cnt_b FROM stock_deposito WHERE cod_vino = v_vino_b;
    SELECT count(*) INTO v_cnt_sala
      FROM stock_sala
     WHERE id_sala = 1 AND cod_vino IN (v_vino_a, v_vino_b, v_vino_c);

    IF v_estado IS DISTINCT FROM 'terminado'
       OR v_dep_a IS DISTINCT FROM 50
       OR v_dep_c IS DISTINCT FROM 50
       OR v_cnt_b <> 0
       OR v_cnt_sala <> 0 THEN
        RAISE EXCEPTION 'FAIL: hubo cambios a medias (estado=%, a=%, c=%, b=%, sala=%)',
            v_estado, v_dep_a, v_dep_c, v_cnt_b, v_cnt_sala;
    END IF;

    RAISE NOTICE 'OK: transferencia multirrenglon fallida no deja cambios a medias';

    DELETE FROM transferencia WHERE nro_solicitud = v_nro;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino IN (v_vino_a, v_vino_b, v_vino_c);
    DELETE FROM stock_deposito WHERE cod_vino IN (v_vino_a, v_vino_b, v_vino_c);
    DELETE FROM vino WHERE cod_vino IN (v_vino_a, v_vino_b, v_vino_c);
END $$;

-- 13k. Transferencia inexistente: P0002 (mapeado a 404 en docs/contratos.md).
DO $$
DECLARE
    v_inexistente integer;
BEGIN
    SELECT COALESCE(MAX(nro_solicitud), 0) + 1 INTO v_inexistente FROM transferencia;

    BEGIN
        CALL sp_procesar_transferencia(v_inexistente);
        RAISE EXCEPTION 'FAIL: una transferencia inexistente no deberia procesarse';
    EXCEPTION WHEN SQLSTATE 'P0002' THEN
        NULL;
    END;

    RAISE NOTICE 'OK: sp_procesar_transferencia inexistente devuelve P0002';
END $$;

-- 13l. Transferencia terminada sin renglones: P0001 y el estado no cambia.
DO $$
DECLARE
    v_nro    integer;
    v_estado estado_documento;
BEGIN
    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (1, CURRENT_DATE)
    RETURNING nro_solicitud INTO v_nro;

    UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = v_nro;

    BEGIN
        CALL sp_procesar_transferencia(v_nro);
        RAISE EXCEPTION 'FAIL: una transferencia sin renglones no deberia procesarse';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;

    SELECT estado INTO v_estado FROM transferencia WHERE nro_solicitud = v_nro;
    IF v_estado IS DISTINCT FROM 'terminado' THEN
        RAISE EXCEPTION 'FAIL: el estado cambio (estado=%)', v_estado;
    END IF;

    RAISE NOTICE 'OK: sp_procesar_transferencia rechaza documento sin renglones (P0001)';

    DELETE FROM transferencia WHERE nro_solicitud = v_nro;
END $$;

-- =============================================================================
-- Fin de las pruebas de procedimientos (004_procedimientos.sql)
-- =============================================================================

-- =============================================================================
-- 14. Tests de reglas de negocio (plan_tests_26.md)
-- =============================================================================
-- Seccion nueva al final del archivo, despues de la seccion 13. Cada caso es un
-- bloque DO autocontenido: inserta sus propias filas, verifica el resultado,
-- captura el error esperado en un sub-bloque anidado y limpia al final. Las
-- secciones 0 a 13 no se modifican. Los casos U-a/U-b/F-a/F-b son provisionales
-- de la decision D1 (RN-02/03/04): por eso van SIN numero de regla.

-- 14.2 RN-01-a · Precio de venta unico para toda la red: la linea copia el precio vigente
DO $$
DECLARE
    v_vino integer;
    v_cb1  integer;
    v_cb2  integer;
    v_p1   numeric(12,2);
    v_p2   numeric(12,2);
    v_cnt  integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26 RN01 Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, v_vino, 10);

    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1) RETURNING nro_comprobante INTO v_cb1;
    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1) RETURNING nro_comprobante INTO v_cb2;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (v_cb1, v_vino, 1);
    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (v_cb2, v_vino, 1);

    SELECT precio_unitario INTO v_p1
      FROM renglon_comprobante
     WHERE nro_comprobante = v_cb1 AND cod_vino = v_vino;
    SELECT precio_unitario INTO v_p2
      FROM renglon_comprobante
     WHERE nro_comprobante = v_cb2 AND cod_vino = v_vino;

    IF v_p1 IS DISTINCT FROM 1000.00 OR v_p2 IS DISTINCT FROM 1000.00 THEN
        RAISE EXCEPTION 'FAIL: precio_unitario inicial distinto de 1000.00 (cb1=%, cb2=%)', v_p1, v_p2;
    END IF;

    -- Subir el precio vigente dispara RN-13 (auditoria); las lineas viejas no cambian.
    UPDATE vino SET precio_venta = 1500.00 WHERE cod_vino = v_vino;

    SELECT count(*) INTO v_cnt
      FROM renglon_comprobante
     WHERE nro_comprobante IN (v_cb1, v_cb2)
       AND cod_vino = v_vino
       AND precio_unitario = 1000.00;

    IF v_cnt <> 2 THEN
        RAISE EXCEPTION 'FAIL: las lineas viejas no conservan 1000.00 (filas=%)', v_cnt;
    END IF;

    RAISE NOTICE 'OK RN-01-a: precio unitario copiado y lineas viejas intactas tras subir el precio';

    DELETE FROM auditoria_precio WHERE cod_vino = v_vino;
    DELETE FROM comprobante WHERE nro_comprobante IN (v_cb1, v_cb2);
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.3 RN-01-b · Control N/A: el esquema no expone un precio por sala
-- esperado: sin caso de falla; ver plan_tests_26.md §5 RN-01
DO $$
DECLARE
    v_cnt integer;
BEGIN
    SELECT count(*) INTO v_cnt
      FROM information_schema.columns
     WHERE table_schema = current_schema()
       AND table_name IN ('sala', 'stock_sala')
       AND column_name ILIKE '%precio%';

    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'FAIL: sala o stock_sala exponen columnas de precio (n=%)', v_cnt;
    END IF;

    RAISE NOTICE 'OK RN-01-b: sala y stock_sala no exponen columnas de precio';
END $$;

-- 14.4 U-a · Provisional D1: insertar un vino y un cliente validos
DO $$
DECLARE
    v_vino integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26 U-a Vino', 'tinto', 2021, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO cliente (id_cliente, nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, descuento)
    VALUES (9026, 'T26 U-a Cliente', 'socio', 'DNI', '26999001', 'Calle T26 1', 1, '2020-01-01', 10.00);

    RAISE NOTICE 'OK U-a: vino y cliente validos insertados';

    DELETE FROM cliente WHERE tipo_documento = 'DNI' AND nro_documento = '26999001';
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.5 U-b · Provisional D1: duplicados rechazados por UNIQUE  -- esperado: 23505
DO $$
DECLARE
    v_vino integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26 U-b Vino', 'tinto', 2021, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    -- Variante 1: vino duplicado por (nombre_comercial, anada, presentacion_ml).
    BEGIN
        INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
        VALUES ('T26 U-b Vino', 'tinto', 2021, 750, 13.00, 1100.00, '20123456789');
        RAISE EXCEPTION 'FAIL: vino duplicado no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    -- Variante 2: cliente duplicado por (tipo_documento, nro_documento).
    BEGIN
        INSERT INTO cliente (nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, descuento)
        VALUES ('T26 U-b Cliente', 'socio', 'DNI', '30123456', 'Calle T26 2', 1, '2020-01-01', 10.00);
        RAISE EXCEPTION 'FAIL: cliente duplicado no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    -- Variante 3: bodega duplicada por CUIT.
    BEGIN
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('20123456789', 'T26 U-b Bodega', 'Calle T26 3');
        RAISE EXCEPTION 'FAIL: bodega duplicada no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    RAISE NOTICE 'OK U-b: duplicados de vino, cliente y bodega rechazados (23505)';

    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.6 F-a · Provisional D1: vino con cuit_bodega existente
DO $$
DECLARE
    v_vino integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26 F-a Vino', 'tinto', 2021, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    IF NOT EXISTS (SELECT 1 FROM vino WHERE cod_vino = v_vino) THEN
        RAISE EXCEPTION 'FAIL: vino con bodega existente no se inserto';
    END IF;

    RAISE NOTICE 'OK F-a: vino con cuit_bodega existente insertado';

    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.7 F-b · Provisional D1: FK inexistente rechazada  -- esperado: 23503
DO $$
DECLARE
    v_nro integer;
BEGIN
    -- Variante 1: vino con cuit_bodega inexistente.
    BEGIN
        INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
        VALUES ('T26 F-b Vino', 'tinto', 2021, 750, 14.00, 1000.00, '99999999999');
        RAISE EXCEPTION 'FAIL: vino con cuit_bodega inexistente no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    -- Variante 2: renglon de transferencia con cod_vino inexistente.
    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (1, CURRENT_DATE) RETURNING nro_solicitud INTO v_nro;

    BEGIN
        INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
        VALUES (v_nro, 999999, 1);
        RAISE EXCEPTION 'FAIL: renglon con cod_vino inexistente no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    RAISE NOTICE 'OK F-b: FK de bodega y de vino inexistentes rechazadas (23503)';

    DELETE FROM transferencia WHERE nro_solicitud = v_nro;
END $$;

-- 14.8 RN-05-a · Composicion 40 + 60: el vino nuevo pasa la validacion diferida
DO $$
DECLARE
    v_vino integer;
    v_suma numeric(5,2);
BEGIN
    INSERT INTO cepa (id_cepa, nombre, tipo)
    VALUES (902601, 'T26W2 Cepa A', 'tinta'),
           (902602, 'T26W2 Cepa B', 'tinta');

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W2 RN05-a Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (v_vino, 902601, 40.00);
    INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (v_vino, 902602, 60.00);

    SELECT SUM(porcentaje) INTO v_suma
      FROM composicion
     WHERE cod_vino = v_vino;

    IF v_suma IS DISTINCT FROM 100.00 THEN
        RAISE EXCEPTION 'FAIL: la composicion suma % y no 100.00', v_suma;
    END IF;

    RAISE NOTICE 'OK RN-05-a: composicion 40 + 60 suma 100 sin error';

    -- El CASCADE de composicion se lleva las dos filas.
    DELETE FROM vino WHERE cod_vino = v_vino;
    DELETE FROM cepa WHERE id_cepa IN (902601, 902602);
END $$;

-- 14.9 RN-05-b · Composicion 60 + 30: la validacion diferida rechaza el vino
-- esperado: P0001 al COMMIT (aqui forzado con SET CONSTRAINTS IMMEDIATE)
DO $$
DECLARE
    v_vino      integer;
    v_msg       text;
    v_restantes integer;
BEGIN
    INSERT INTO cepa (id_cepa, nombre, tipo)
    VALUES (902603, 'T26W2 Cepa C', 'tinta'),
           (902604, 'T26W2 Cepa D', 'tinta');

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W2 RN05-b Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    BEGIN
        INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (v_vino, 902603, 60.00);
        INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (v_vino, 902604, 30.00);
        -- Adelanta el disparo diferido al punto actual del bloque.
        SET CONSTRAINTS tg_composicion_cien IMMEDIATE;
        RAISE EXCEPTION 'FAIL: composicion 60 + 30 no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg NOT LIKE '[RN-05]%' THEN
            RAISE EXCEPTION 'FAIL: falta el prefijo [RN-05]: %', v_msg;
        END IF;
        IF v_msg <> format('[RN-05] La composicion del vino %s suma 90.00, debe sumar 100', v_vino) THEN
            RAISE EXCEPTION 'FAIL: mensaje inesperado: %', v_msg;
        END IF;
    END;

    -- El rollback del sub-bloque deshace las dos filas de composicion.
    SELECT count(*) INTO v_restantes
      FROM composicion
     WHERE cod_vino = v_vino;
    IF v_restantes <> 0 THEN
        RAISE EXCEPTION 'FAIL: el sub-bloque dejo % filas de composicion', v_restantes;
    END IF;

    RAISE NOTICE 'OK RN-05-b: composicion 60 + 30 rechazada con [RN-05] al forzar el trigger';

    DELETE FROM vino WHERE cod_vino = v_vino;
    DELETE FROM cepa WHERE id_cepa IN (902603, 902604);
END $$;

-- 14.10 RN-05-c · Composicion diferida: 60 solo no falla y completar con 40 tampoco
DO $$
DECLARE
    v_vino integer;
    v_suma numeric(5,2);
BEGIN
    INSERT INTO cepa (id_cepa, nombre, tipo)
    VALUES (902605, 'T26W2 Cepa E', 'tinta'),
           (902606, 'T26W2 Cepa F', 'tinta');

    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W2 RN05-c Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    -- Si la validacion fuera inmediata, este INSERT fallaria: la regla difiere.
    -- El COMMIT real de la transaccion ejecuta el mismo chequeo P0001 cuando la
    -- suma final es distinta de 100; aqui el bloque sigue y la completa.
    INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (v_vino, 902605, 60.00);

    -- Segunda cepa: la composicion queda completa y el bloque no fallo.
    INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (v_vino, 902606, 40.00);

    SELECT SUM(porcentaje) INTO v_suma
      FROM composicion
     WHERE cod_vino = v_vino;

    IF v_suma IS DISTINCT FROM 100.00 THEN
        RAISE EXCEPTION 'FAIL: la composicion suma % y no 100.00', v_suma;
    END IF;

    RAISE NOTICE 'OK RN-05-c: la validacion difiere; 60 solo no fallo y 40 lo completo';

    DELETE FROM vino WHERE cod_vino = v_vino;
    DELETE FROM cepa WHERE id_cepa IN (902605, 902606);
END $$;

-- 14.11 RN-06-a · Descuento por tipo de cliente: mapeo exacto y NULL (STRICT)
DO $$
DECLARE
    v_socio        numeric(5,2);
    v_distribuidor numeric(5,2);
    v_exportador   numeric(5,2);
BEGIN
    v_socio        := fn_descuento_cliente('socio');
    v_distribuidor := fn_descuento_cliente('distribuidor');
    v_exportador   := fn_descuento_cliente('exportador');

    IF v_socio IS DISTINCT FROM 10.00 THEN
        RAISE EXCEPTION 'FAIL: socio devuelve % y no 10.00', v_socio;
    END IF;
    IF v_distribuidor IS DISTINCT FROM 20.00 THEN
        RAISE EXCEPTION 'FAIL: distribuidor devuelve % y no 20.00', v_distribuidor;
    END IF;
    IF v_exportador IS DISTINCT FROM 30.00 THEN
        RAISE EXCEPTION 'FAIL: exportador devuelve % y no 30.00', v_exportador;
    END IF;
    IF fn_descuento_cliente(NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: NULL deberia devolver NULL (STRICT)';
    END IF;

    RAISE NOTICE 'OK RN-06-a: socio 10.00, distribuidor 20.00, exportador 30.00 y NULL';
END $$;

-- 14.12 RN-06-b · Descuento por tipo de cliente: tipo desconocido rechazado
-- esperado: P0001
DO $$
DECLARE
    v_msg text;
BEGIN
    BEGIN
        PERFORM fn_descuento_cliente('desconocido');
        RAISE EXCEPTION 'FAIL: tipo de cliente desconocido no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg <> '[RN-06] Tipo de cliente desconocido: desconocido' THEN
            RAISE EXCEPTION 'FAIL: mensaje inesperado: %', v_msg;
        END IF;
    END;

    RAISE NOTICE 'OK RN-06-b: tipo desconocido rechazado con el mensaje exacto de RN-06';
END $$;

-- 14.13 RN-07-a · Permiso de exportacion con vencimiento posterior a la emision
DO $$
BEGIN
    INSERT INTO permiso_exportacion (id_cliente, cod_permiso, fecha_emision, fecha_vencimiento)
    VALUES (2, 'T26W2-RN07A', '2024-01-01', '2025-01-01');

    RAISE NOTICE 'OK RN-07-a: vencimiento posterior a la emision aceptado';

    DELETE FROM permiso_exportacion WHERE id_cliente = 2 AND cod_permiso = 'T26W2-RN07A';
END $$;

-- 14.14 RN-07-b · Permiso con vencimiento anterior o igual a la emision
-- esperado: 23514
DO $$
DECLARE
    v_constraint text;
BEGIN
    -- Variante 1: vencimiento anterior a la emision.
    BEGIN
        INSERT INTO permiso_exportacion (id_cliente, cod_permiso, fecha_emision, fecha_vencimiento)
        VALUES (2, 'T26W2-RN07B1', '2025-01-01', '2024-01-01');
        RAISE EXCEPTION 'FAIL: vencimiento anterior a la emision no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint IS DISTINCT FROM 'ck_permiso_fechas' THEN
            RAISE EXCEPTION 'FAIL: constraint inesperado: %', v_constraint;
        END IF;
    END;

    -- Variante 2: vencimiento igual a la emision.
    BEGIN
        INSERT INTO permiso_exportacion (id_cliente, cod_permiso, fecha_emision, fecha_vencimiento)
        VALUES (2, 'T26W2-RN07B2', '2025-01-01', '2025-01-01');
        RAISE EXCEPTION 'FAIL: vencimiento igual a la emision no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint IS DISTINCT FROM 'ck_permiso_fechas' THEN
            RAISE EXCEPTION 'FAIL: constraint inesperado: %', v_constraint;
        END IF;
    END;

    RAISE NOTICE 'OK RN-07-b: vencimiento anterior o igual a la emision rechazado por ck_permiso_fechas';

    DELETE FROM permiso_exportacion
     WHERE id_cliente = 2 AND cod_permiso IN ('T26W2-RN07B1', 'T26W2-RN07B2');
END $$;

-- 14.15 RN-08-a · Calculo de importes de linea y de cabecera: socio 10 % y redondeo
DO $$
DECLARE
    v_vino1 integer;
    v_vino2 integer;
    v_cb1   integer;
    v_cb2   integer;
    v_prec  numeric(12,2);
    v_desc  numeric(12,2);
    v_sub   numeric(12,2);
    v_cab   record;
BEGIN
    -- Caso base: precio 1000.00, cantidad 3, cliente socio (10 %).
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W3 RN08-a Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino1;

    -- Variante de redondeo: precio 0.33, cantidad 1.
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W3 RN08-a Redondeo', 'tinto', 2020, 750, 14.00, 0.33, '20123456789')
    RETURNING cod_vino INTO v_vino2;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    VALUES (1, v_vino1, 10), (1, v_vino2, 10);

    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1) RETURNING nro_comprobante INTO v_cb1;
    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1) RETURNING nro_comprobante INTO v_cb2;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_cb1, v_vino1, 3);

    SELECT precio_unitario, descuento, subtotal
      INTO v_prec, v_desc, v_sub
      FROM renglon_comprobante
     WHERE nro_comprobante = v_cb1 AND cod_vino = v_vino1;

    IF v_prec IS DISTINCT FROM 1000.00 THEN
        RAISE EXCEPTION 'FAIL: precio_unitario es % y no 1000.00', v_prec;
    END IF;
    IF v_desc IS DISTINCT FROM 300.00 THEN
        RAISE EXCEPTION 'FAIL: descuento de linea es % y no 300.00', v_desc;
    END IF;
    IF v_sub IS DISTINCT FROM 2700.00 THEN
        RAISE EXCEPTION 'FAIL: subtotal de linea es % y no 2700.00', v_sub;
    END IF;

    -- T2 recalcula la cabecera: 3000.00, 300.00, 2700.00.
    SELECT subtotal, descuento, total INTO v_cab
      FROM comprobante
     WHERE nro_comprobante = v_cb1;

    IF v_cab.subtotal IS DISTINCT FROM 3000.00
       OR v_cab.descuento IS DISTINCT FROM 300.00
       OR v_cab.total IS DISTINCT FROM 2700.00 THEN
        RAISE EXCEPTION 'FAIL: cabecera (%, %, %) distinta de (3000.00, 300.00, 2700.00)',
            v_cab.subtotal, v_cab.descuento, v_cab.total;
    END IF;

    -- ck_comprobante_total exige total = subtotal - descuento.
    IF v_cab.total IS DISTINCT FROM (v_cab.subtotal - v_cab.descuento) THEN
        RAISE EXCEPTION 'FAIL: ck_comprobante_total no se cumple en la cabecera';
    END IF;

    -- Variante de redondeo: 0.33 * 10 % = 0.033 -> 0.03; subtotal 0.30.
    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_cb2, v_vino2, 1);

    SELECT precio_unitario, descuento, subtotal
      INTO v_prec, v_desc, v_sub
      FROM renglon_comprobante
     WHERE nro_comprobante = v_cb2 AND cod_vino = v_vino2;

    IF v_prec IS DISTINCT FROM 0.33 THEN
        RAISE EXCEPTION 'FAIL: precio_unitario de redondeo es % y no 0.33', v_prec;
    END IF;
    IF v_desc IS DISTINCT FROM 0.03 THEN
        RAISE EXCEPTION 'FAIL: descuento de redondeo es % y no 0.03', v_desc;
    END IF;
    IF v_sub IS DISTINCT FROM 0.30 THEN
        RAISE EXCEPTION 'FAIL: subtotal de redondeo es % y no 0.30', v_sub;
    END IF;

    RAISE NOTICE 'OK RN-08-a: lineas y cabecera calculadas con socio del 10 por ciento y redondeo a 2 decimales';

    -- Los renglones caen con el CASCADE de comprobante.
    DELETE FROM comprobante WHERE nro_comprobante IN (v_cb1, v_cb2);
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino IN (v_vino1, v_vino2);
    DELETE FROM vino WHERE cod_vino IN (v_vino1, v_vino2);
END $$;

-- 14.16 RN-08-b · Calculo de importes: N/A justificado
-- esperado: sin caso de falla; ver plan_tests_26.md §5 RN-08
DO $$
BEGIN
    RAISE NOTICE 'OK RN-08-b: sin caso de falla; los limites los fijan los CHECK de 002';
END $$;

-- 14.17 RN-09-a · Stock suficiente: vender exactamente el disponible
DO $$
DECLARE
    v_vino  integer;
    v_cb    integer;
    v_disp  integer;
    v_cab   record;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W3 RN09-a Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, v_vino, 10);

    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1) RETURNING nro_comprobante INTO v_cb;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_cb, v_vino, 10);

    -- T2 descuenta el stock vendido.
    SELECT cantidad INTO v_disp
      FROM stock_sala
     WHERE id_sala = 1 AND cod_vino = v_vino;

    IF v_disp IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'FAIL: el stock quedo en % y no en 0', v_disp;
    END IF;

    -- Cabecera: bruto 10000.00, descuento socio 1000.00, total 9000.00.
    SELECT subtotal, descuento, total INTO v_cab
      FROM comprobante
     WHERE nro_comprobante = v_cb;

    IF v_cab.subtotal IS DISTINCT FROM 10000.00
       OR v_cab.descuento IS DISTINCT FROM 1000.00
       OR v_cab.total IS DISTINCT FROM 9000.00 THEN
        RAISE EXCEPTION 'FAIL: cabecera (%, %, %) distinta de (10000.00, 1000.00, 9000.00)',
            v_cab.subtotal, v_cab.descuento, v_cab.total;
    END IF;

    RAISE NOTICE 'OK RN-09-a: venta del stock justo aceptada; stock en 0 y cabecera cuadrada';

    DELETE FROM comprobante WHERE nro_comprobante = v_cb;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.18 RN-09-b · Stock insuficiente: vender 11 con 10 disponibles
-- esperado: P0001
DO $$
DECLARE
    v_vino   integer;
    v_cb     integer;
    v_msg    text;
    v_disp   integer;
    v_cnt    integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W3 RN09-b Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, v_vino, 10);

    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1) RETURNING nro_comprobante INTO v_cb;

    BEGIN
        INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
        VALUES (v_cb, v_vino, 11);
        RAISE EXCEPTION 'FAIL: vender 11 con stock 10 no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg NOT LIKE '[RN-09] %' THEN
            RAISE EXCEPTION 'FAIL: falta el prefijo [RN-09]: %', v_msg;
        END IF;
        IF v_msg <> format('[RN-09] Stock insuficiente del vino %s en la sala %s: disponible %s, solicitado %s',
                            v_vino, 1, 10, 11) THEN
            RAISE EXCEPTION 'FAIL: mensaje inesperado: %', v_msg;
        END IF;
    END;

    -- El sub-bloque revierte: stock intacto y comprobante sin renglones.
    SELECT cantidad INTO v_disp
      FROM stock_sala
     WHERE id_sala = 1 AND cod_vino = v_vino;

    IF v_disp IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'FAIL: el stock quedo en % y no en 10', v_disp;
    END IF;

    SELECT count(*) INTO v_cnt
      FROM renglon_comprobante
     WHERE nro_comprobante = v_cb;

    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'FAIL: el comprobante quedo con % renglones', v_cnt;
    END IF;

    RAISE NOTICE 'OK RN-09-b: venta de 11 con stock 10 rechazada con [RN-09]; nada cambio';

    DELETE FROM comprobante WHERE nro_comprobante = v_cb;
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.19 RN-09-c · Stock insuficiente: vino sin fila en stock_sala (disponible 0)
-- esperado: P0001
DO $$
DECLARE
    v_vino integer;
    v_cb   integer;
    v_msg  text;
    v_cnt  integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W3 RN09-c Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1) RETURNING nro_comprobante INTO v_cb;

    BEGIN
        INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
        VALUES (v_cb, v_vino, 1);
        RAISE EXCEPTION 'FAIL: vender un vino sin stock no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg NOT LIKE '[RN-09] %' THEN
            RAISE EXCEPTION 'FAIL: falta el prefijo [RN-09]: %', v_msg;
        END IF;
        IF v_msg <> format('[RN-09] Stock insuficiente del vino %s en la sala %s: disponible %s, solicitado %s',
                            v_vino, 1, 0, 1) THEN
            RAISE EXCEPTION 'FAIL: mensaje inesperado: %', v_msg;
        END IF;
    END;

    SELECT count(*) INTO v_cnt
      FROM renglon_comprobante
     WHERE nro_comprobante = v_cb;

    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'FAIL: el comprobante quedo con % renglones', v_cnt;
    END IF;

    RAISE NOTICE 'OK RN-09-c: vino sin fila de stock rechazado con [RN-09] y disponible 0';

    DELETE FROM comprobante WHERE nro_comprobante = v_cb;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.20 RN-13-a · Auditoria de precio con app.usuario: 1 fila con el usuario y los importes
DO $$
DECLARE
    v_vino      integer;
    v_cnt       integer;
    v_usuario   text;
    v_anterior  numeric(12,2);
    v_nuevo     numeric(12,2);
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W4 RN13-a Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    -- Usuario de aplicacion, transaction-local (no sobrevive al bloque).
    PERFORM set_config('app.usuario', 'test@bodega.com', true);

    UPDATE vino SET precio_venta = 1500.00 WHERE cod_vino = v_vino;

    SELECT count(*) INTO v_cnt
      FROM auditoria_precio
     WHERE cod_vino = v_vino;

    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'FAIL: se esperaba 1 fila de auditoria y hay %', v_cnt;
    END IF;

    SELECT usuario, precio_anterior, precio_nuevo
      INTO v_usuario, v_anterior, v_nuevo
      FROM auditoria_precio
     WHERE cod_vino = v_vino;

    IF v_usuario IS DISTINCT FROM 'test@bodega.com' THEN
        RAISE EXCEPTION 'FAIL: usuario de auditoria es % y no test@bodega.com', v_usuario;
    END IF;
    IF v_anterior IS DISTINCT FROM 1000.00 THEN
        RAISE EXCEPTION 'FAIL: precio_anterior es % y no 1000.00', v_anterior;
    END IF;
    IF v_nuevo IS DISTINCT FROM 1500.00 THEN
        RAISE EXCEPTION 'FAIL: precio_nuevo es % y no 1500.00', v_nuevo;
    END IF;

    RAISE NOTICE 'OK RN-13-a: cambio de precio auditado con app.usuario e importes correctos';

    -- auditoria_precio referencia a vino con RESTRICT: la auditoria cae primero.
    DELETE FROM auditoria_precio WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.21 RN-13-b · Update de otro atributo: no audita (la clausula WHEN descarta)
DO $$
DECLARE
    v_vino integer;
    v_cnt  integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W4 RN13-b Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    -- El UPDATE no debe fallar y no debe dejar filas de auditoria.
    UPDATE vino SET nombre_comercial = 'T26W4 RN13-b Vino Renombrado'
     WHERE cod_vino = v_vino;

    SELECT count(*) INTO v_cnt
      FROM auditoria_precio
     WHERE cod_vino = v_vino;

    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'FAIL: cambiar otro atributo genero % filas de auditoria', v_cnt;
    END IF;

    RAISE NOTICE 'OK RN-13-b: cambiar nombre_comercial no genero auditoria de precio';

    DELETE FROM auditoria_precio WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.22 RN-13-c · Auditoria de precio sin app.usuario: usuario = current_user
DO $$
DECLARE
    v_vino     integer;
    v_cnt      integer;
    v_usuario  text;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W4 RN13-c Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    -- Vacio explicito: el setting local del bloque anterior no debe filtrarse.
    PERFORM set_config('app.usuario', '', true);

    UPDATE vino SET precio_venta = 1200.00 WHERE cod_vino = v_vino;

    SELECT count(*) INTO v_cnt
      FROM auditoria_precio
     WHERE cod_vino = v_vino;

    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'FAIL: se esperaba 1 fila de auditoria y hay %', v_cnt;
    END IF;

    SELECT usuario INTO v_usuario
      FROM auditoria_precio
     WHERE cod_vino = v_vino;

    IF v_usuario IS DISTINCT FROM current_user::text THEN
        RAISE EXCEPTION 'FAIL: usuario de auditoria es % y no current_user %', v_usuario, current_user;
    END IF;

    RAISE NOTICE 'OK RN-13-c: sin app.usuario la auditoria registra current_user';

    DELETE FROM auditoria_precio WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.23 RN-14-a · Vino sin movimientos: el DELETE funciona
DO $$
DECLARE
    v_vino integer;
    v_cnt  integer;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W4 RN14-a Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    DELETE FROM vino WHERE cod_vino = v_vino;

    SELECT count(*) INTO v_cnt
      FROM vino
     WHERE cod_vino = v_vino;

    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'FAIL: el vino sin movimientos no se borro';
    END IF;

    RAISE NOTICE 'OK RN-14-a: vino sin movimientos borrado correctamente';
END $$;

-- 14.24 RN-14-b · Vino con renglon_comprobante: el DELETE falla por RESTRICT
-- esperado: 23503
DO $$
DECLARE
    v_vino       integer;
    v_cb         integer;
    v_constraint text;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W4 RN14-b Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    -- T1 exige stock para poder insertar el renglon: flujo de venta.
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, v_vino, 1);

    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1) RETURNING nro_comprobante INTO v_cb;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_cb, v_vino, 1);

    -- Se quita la fila de stock (ya en 0) para que la unica referencia al vino
    -- sea el renglon y el constraint reportado sea el esperado.
    DELETE FROM stock_sala WHERE id_sala = 1 AND cod_vino = v_vino;

    BEGIN
        DELETE FROM vino WHERE cod_vino = v_vino;
        RAISE EXCEPTION 'FAIL: borrar un vino con renglon_comprobante no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint IS DISTINCT FROM 'fk_renglon_comprobante_vino' THEN
            RAISE EXCEPTION 'FAIL: constraint inesperado: %', v_constraint;
        END IF;
    END;

    RAISE NOTICE 'OK RN-14-b: vino con renglon_comprobante no se borra (fk_renglon_comprobante_vino)';

    -- El renglon cae con el CASCADE del comprobante; luego el vino.
    DELETE FROM comprobante WHERE nro_comprobante = v_cb;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.25 RN-14-c · Vino con auditoria_precio: el DELETE falla por RESTRICT
-- esperado: 23503
DO $$
DECLARE
    v_vino       integer;
    v_constraint text;
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W4 RN14-c Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    -- Un cambio de precio deja una fila en auditoria_precio (RN-13).
    UPDATE vino SET precio_venta = 1100.00 WHERE cod_vino = v_vino;

    BEGIN
        DELETE FROM vino WHERE cod_vino = v_vino;
        RAISE EXCEPTION 'FAIL: borrar un vino con auditoria_precio no fallo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint IS DISTINCT FROM 'fk_auditoria_precio_vino' THEN
            RAISE EXCEPTION 'FAIL: constraint inesperado: %', v_constraint;
        END IF;
    END;

    RAISE NOTICE 'OK RN-14-c: vino con auditoria_precio no se borra (fk_auditoria_precio_vino)';

    DELETE FROM auditoria_precio WHERE cod_vino = v_vino;
    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.26 RN-15-a · Graduacion dentro del rango: 14.00 aceptada
DO $$
DECLARE
    v_vino  integer;
    v_grad  numeric(4,2);
BEGIN
    INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
    VALUES ('T26W4 RN15-a Vino', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789')
    RETURNING cod_vino INTO v_vino;

    SELECT graduacion INTO v_grad
      FROM vino
     WHERE cod_vino = v_vino;

    IF v_grad IS DISTINCT FROM 14.00 THEN
        RAISE EXCEPTION 'FAIL: graduacion almacenada es % y no 14.00', v_grad;
    END IF;

    RAISE NOTICE 'OK RN-15-a: graduacion 14.00 aceptada';

    DELETE FROM vino WHERE cod_vino = v_vino;
END $$;

-- 14.27 RN-15-b · Graduacion fuera del rango: 25.00 rechazada
-- esperado: 23514
DO $$
DECLARE
    v_constraint text;
BEGIN
    BEGIN
        INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
        VALUES ('T26W4 RN15-b Vino', 'tinto', 2020, 750, 25.00, 1000.00, '20123456789');
        RAISE EXCEPTION 'FAIL: graduacion 25.00 no deberia permitirse' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint IS DISTINCT FROM 'ck_vino_graduacion' THEN
            RAISE EXCEPTION 'FAIL: constraint inesperado: %', v_constraint;
        END IF;
    END;

    RAISE NOTICE 'OK RN-15-b: graduacion 25.00 rechazada por ck_vino_graduacion';

    -- El sub-bloque revierte el INSERT: no hay nada que limpiar.
    DELETE FROM vino WHERE nombre_comercial = 'T26W4 RN15-b Vino';
END $$;
