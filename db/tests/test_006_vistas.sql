-- =============================================================================
-- test_006_vistas.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Pruebas de compatibilidad de las vistas de 006 contra 001–005.
--
-- Ejecución (sobre una base recién inicializada con 001 → 007):
--   psql -v ON_ERROR_STOP=1 -f db/tests/test_006_vistas.sql
--
-- Estrategia:
--   * Todo ocurre dentro de BEGIN … ROLLBACK: la prueba no deja residuos.
--   * Los datos se siembran por el camino normal de escritura para que los
--     triggers de 005 calculen importes, descuenten stock y mantengan la
--     cabecera (RN-08, RN-09). No se escriben importes derivados a mano.
--   * Cada aserción compara la vista contra la función contratada
--     (fn_stock_sala, fn_total_comprobante) o contra los totales que mantiene
--     005, y además contra un valor calculado a mano a partir de las cantidades
--     sembradas. Así la prueba no es tautológica: si vista y función divergen
--     en el mismo sentido, el literal independiente igual falla.
--   * SET CONSTRAINTS ALL IMMEDIATE dispara la verificación diferida de RN-05
--     dentro de la transacción; un ROLLBACK no ejecutaría el constraint trigger.
--   * La precondición de base limpia se verifica en runtime antes de sembrar:
--     si la base no está recién inicializada, la prueba falla con un mensaje
--     claro en lugar de violaciones de UNIQUE confusas.
--
-- Estado esperado con 001 → 007 aplicadas: todas las aserciones pasan. No hay
-- divergencia entre las vistas y las funciones contratadas; A0–A6 son prueba de
-- regresión de esa compatibilidad (ver 006_vistas.sql, encabezado). A6 además
-- cubre R-015: el bucket mensual no depende del TimeZone de la sesión.
--
-- Mensajes de error: identifican la vista y el valor observado.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Precondición: base recién inicializada con 001 → 007 (verificación explícita).
-- Sin este chequeo, en una base reutilizada los INSERT de abajo fallan con
-- violaciones de UNIQUE ajenas y la prueba da un falso negativo confuso.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM localidad      WHERE id_localidad = 9001)
       OR EXISTS (SELECT 1 FROM cepa        WHERE id_cepa IN (9001, 9002))
       OR EXISTS (SELECT 1 FROM maridaje    WHERE id_maridaje = 9001)
       OR EXISTS (SELECT 1 FROM bodega      WHERE cuit = '20000000006')
       OR EXISTS (SELECT 1 FROM transportista WHERE id_transportista = 9001)
       OR EXISTS (SELECT 1 FROM sala        WHERE id_sala IN (9001, 9002))
       OR EXISTS (SELECT 1 FROM cliente     WHERE id_cliente = 9001)
       OR EXISTS (SELECT 1 FROM vino        WHERE nombre_comercial LIKE 'Vino Test 006%')
       OR EXISTS (SELECT 1 FROM comprobante WHERE nro_comprobante BETWEEN 9001 AND 9002)
       OR EXISTS (SELECT 1 FROM ingreso     WHERE cod_ingreso BETWEEN 9001 AND 9003)
       OR EXISTS (SELECT 1 FROM transferencia WHERE nro_solicitud BETWEEN 9001 AND 9003)
    THEN
        RAISE EXCEPTION 'test_006_vistas: la base no está limpia; ejecutar sobre una base recién inicializada con 001 → 007';
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 0. Datos mínimos: catálogos y entidades sin dependencias
-- -----------------------------------------------------------------------------
INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
VALUES (9001, '5600', 'Localidad Test 006', 'Mendoza', 'Encargado Test 006');

INSERT INTO cepa (id_cepa, nombre, tipo)
VALUES (9001, 'Malbec Test 006', 'tinta'),
       (9002, 'Cabernet Test 006', 'tinta');

INSERT INTO maridaje (id_maridaje, nombre, temperatura_servicio)
VALUES (9001, 'Carnes Test 006', 18.0);

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20000000006', 'Bodega Test 006', 'Calle Bodega 006');

INSERT INTO transportista (id_transportista, razon_social, cuit, email, telefono, domicilio)
VALUES (9001, 'Transportista Test 006', '20000000016', 'test006@test.com', '2620000006', 'Calle Transporte 006');

INSERT INTO sala (id_sala, direccion, dia_cierre_semanal, id_localidad)
VALUES (9001, 'Sala Norte Test 006', 2, 9001),
       (9002, 'Sala Sur Test 006', 3, 9001);

-- Cliente socio: descuento es GENERATED ALWAYS AS (fn_descuento_cliente(tipo))
-- STORED, así que NO se incluye en el INSERT: la base lo calcula. Para
-- 'socio' el valor esperado es 10.00 (RN-06); se verifica abajo.
INSERT INTO cliente (id_cliente, nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta)
VALUES (9001, 'Cliente Test 006', 'socio', 'DNI', '90000001', 'Calle Cliente 006', 9001, DATE '2020-01-01');

-- A0. La columna generada descuento coincide con fn_descuento_cliente(tipo)
--     y con el literal independiente 10.00 del cliente socio sembrado.
DO $$
DECLARE
    v_desc numeric(5,2);
    v_fn   numeric(5,2);
BEGIN
    SELECT c.descuento, fn_descuento_cliente(c.tipo)
      INTO v_desc, v_fn
      FROM cliente AS c
     WHERE c.id_cliente = 9001;

    IF v_desc IS NULL THEN
        RAISE EXCEPTION 'cliente 9001 no tiene descuento generado';
    END IF;

    IF v_desc IS DISTINCT FROM v_fn THEN
        RAISE EXCEPTION 'descuento generado (%) difiere de fn_descuento_cliente(tipo) (%)',
            v_desc, v_fn;
    END IF;

    IF v_desc <> 10.00 THEN
        RAISE EXCEPTION 'cliente socio: descuento generado = %, esperado 10.00', v_desc;
    END IF;

    RAISE NOTICE 'OK A0: cliente.descuento es GENERATED y coincide con fn_descuento_cliente(tipo)';
END $$;

-- cod_vino es GENERATED ALWAYS: se referencia por nombre en el resto del script.
INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
VALUES ('Vino Test 006 A', 'tinto', 2021, 750, 13.50, 1000.00, '20000000006'),
       ('Vino Test 006 B', 'tinto', 2021, 750, 13.50, 2000.00, '20000000006'),
       ('Vino Test 006 C', 'blanco', 2022, 750, 12.00, 1500.00, '20000000006');

-- Composición de A: 60 + 40 = 100 (RN-05 se verifica diferido; ver abajo).
INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
VALUES ((SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 A'), 9001, 60.00),
       ((SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 A'), 9002, 40.00);

INSERT INTO vino_maridaje (cod_vino, id_maridaje)
VALUES ((SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 A'), 9001);

-- -----------------------------------------------------------------------------
-- 1. Stock inicial. A: depósito 100 y salas 10 + 5. B: depósito 50 y sala 8.
--    C queda sin filas de stock (caso borde de los COALESCE).
-- -----------------------------------------------------------------------------
INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES ((SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 A'), 100),
       ((SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 B'), 50);

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (9001, (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 A'), 10),
       (9002, (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 A'), 5),
       (9001, (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 B'), 8);

-- -----------------------------------------------------------------------------
-- 2. Ventas por el camino normal: la API envía solo (nro_comprobante, cod_vino,
--    cantidad). El BEFORE completa precio_unitario, descuento y subtotal; el
--    AFTER descuenta stock y recalcula la cabecera.
--    Marzo: A x3 (bruto 3000) y B x2 (bruto 4000) → total 6300.
--    Abril: B x1 (bruto 2000) → total 1800.
-- -----------------------------------------------------------------------------
INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala)
VALUES (9001, DATE '2026-03-15', 9001, 9001),
       (9002, DATE '2026-04-10', 9001, 9001);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
VALUES (9001, (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 A'), 3),
       (9001, (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 B'), 2),
       (9002, (SELECT cod_vino FROM vino WHERE nombre_comercial = 'Vino Test 006 B'), 1);

-- -----------------------------------------------------------------------------
-- 3. Documentos pendientes. El alta solo acepta en_confeccion (RN-10/RN-11);
--    el avance de estado también pasa por el trigger.
--      9001: en_confeccion  → pendiente
--      9002: terminado      → pendiente
--      9003: procesado      → NO pendiente
-- -----------------------------------------------------------------------------
INSERT INTO ingreso (cod_ingreso, fecha, id_transportista, cuit_bodega)
VALUES (9001, DATE '2026-03-01', 9001, '20000000006'),
       (9002, DATE '2026-03-02', 9001, '20000000006'),
       (9003, DATE '2026-03-03', 9001, '20000000006');

INSERT INTO transferencia (nro_solicitud, id_sala)
VALUES (9001, 9001),
       (9002, 9001),
       (9003, 9001);

UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = 9002;
UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = 9003;
UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 9003;

UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = 9002;
UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = 9003;
UPDATE transferencia SET estado = 'procesado' WHERE nro_solicitud = 9003;

-- RN-05 está diferido: sin esto el chequeo de composición no corre en la prueba.
SET CONSTRAINTS ALL IMMEDIATE;

-- -----------------------------------------------------------------------------
-- A1. Las cuatro vistas existen y responden.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_n integer;
BEGIN
    SELECT count(*) INTO v_n
      FROM pg_views
     WHERE schemaname = 'public'
       AND viewname IN (
           'vw_stock_total_vino',
           'vw_ventas_mensuales_sala',
           'vw_documentos_pendientes',
           'vw_ficha_vino'
       );

    IF v_n <> 4 THEN
        RAISE EXCEPTION 'Se esperaban 4 vistas de reporte y se encontraron %', v_n;
    END IF;

    PERFORM 1 FROM vw_stock_total_vino    LIMIT 1;
    PERFORM 1 FROM vw_ventas_mensuales_sala LIMIT 1;
    PERFORM 1 FROM vw_documentos_pendientes LIMIT 1;
    PERFORM 1 FROM vw_ficha_vino          LIMIT 1;

    RAISE NOTICE 'OK A1: las cuatro vistas existen y responden';
END $$;

-- -----------------------------------------------------------------------------
-- A2. vw_stock_total_vino coincide con stock_deposito, con la suma de
--     fn_stock_sala por sala y con el total calculado a mano.
--     A: sala 9001 = 10 - 3 = 7, sala 9002 = 5  → salas 12; depósito 100; total 112.
--     B: sala 9001 = 8 - 2 - 1 = 5             → salas 5;  depósito 50;  total 55.
--     C: sin filas                              → salas 0;  depósito 0;   total 0.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_cod       integer;
    v_dep       integer;
    v_salas     bigint;
    v_total     integer;
    v_dep_fn    integer;
    v_salas_fn  bigint;
BEGIN
    -- Vino A (con stock en dos salas y una venta).
    SELECT cod_vino INTO v_cod FROM vino WHERE nombre_comercial = 'Vino Test 006 A';
    IF v_cod IS NULL THEN
        RAISE EXCEPTION 'No se encontró el vino de prueba A';
    END IF;

    SELECT stock_deposito, stock_salas, stock_total
      INTO v_dep, v_salas, v_total
      FROM vw_stock_total_vino
     WHERE cod_vino = v_cod;

    IF v_total IS NULL THEN
        RAISE EXCEPTION 'vw_stock_total_vino no devolvió fila para el vino A';
    END IF;

    SELECT cantidad INTO v_dep_fn FROM stock_deposito WHERE cod_vino = v_cod;
    SELECT COALESCE(SUM(fn_stock_sala(s.id_sala, v_cod)), 0) INTO v_salas_fn
      FROM sala AS s;

    IF v_dep <> COALESCE(v_dep_fn, 0) THEN
        RAISE EXCEPTION 'vw_stock_total_vino.stock_deposito (%) difiere de stock_deposito (%)',
            v_dep, v_dep_fn;
    END IF;

    IF v_salas <> v_salas_fn THEN
        RAISE EXCEPTION 'vw_stock_total_vino.stock_salas (%) difiere de la suma de fn_stock_sala (%)',
            v_salas, v_salas_fn;
    END IF;

    IF v_total <> v_dep + v_salas THEN
        RAISE EXCEPTION 'vw_stock_total_vino.stock_total (%) no es depósito + salas (% + %)',
            v_total, v_dep, v_salas;
    END IF;

    IF v_dep <> 100 OR v_salas <> 12 OR v_total <> 112 THEN
        RAISE EXCEPTION 'Vino A: se esperaban (100, 12, 112) y se obtuvo (%, %, %)',
            v_dep, v_salas, v_total;
    END IF;

    -- Vino B (stock en una sala y dos ventas).
    SELECT cod_vino INTO v_cod FROM vino WHERE nombre_comercial = 'Vino Test 006 B';

    SELECT stock_deposito, stock_salas, stock_total
      INTO v_dep, v_salas, v_total
      FROM vw_stock_total_vino
     WHERE cod_vino = v_cod;

    SELECT cantidad INTO v_dep_fn FROM stock_deposito WHERE cod_vino = v_cod;
    SELECT COALESCE(SUM(fn_stock_sala(s.id_sala, v_cod)), 0) INTO v_salas_fn
      FROM sala AS s;

    IF v_total IS NULL OR v_dep <> COALESCE(v_dep_fn, 0) OR v_salas <> v_salas_fn THEN
        RAISE EXCEPTION 'Vino B: vista (dep=%, salas=%, total=%) vs stock_deposito=% y fn_stock_sala=%',
            v_dep, v_salas, v_total, v_dep_fn, v_salas_fn;
    END IF;

    IF v_dep <> 50 OR v_salas <> 5 OR v_total <> 55 THEN
        RAISE EXCEPTION 'Vino B: se esperaban (50, 5, 55) y se obtuvo (%, %, %)',
            v_dep, v_salas, v_total;
    END IF;

    -- Vino C (sin filas de stock): COALESCE debe devolver 0, no NULL.
    SELECT cod_vino INTO v_cod FROM vino WHERE nombre_comercial = 'Vino Test 006 C';

    SELECT stock_deposito, stock_salas, stock_total
      INTO v_dep, v_salas, v_total
      FROM vw_stock_total_vino
     WHERE cod_vino = v_cod;

    IF v_total IS NULL OR v_dep IS NULL OR v_salas IS NULL THEN
        RAISE EXCEPTION 'Vino C sin stock: la vista devolvió NULL en vez de 0';
    END IF;

    SELECT COALESCE(SUM(fn_stock_sala(s.id_sala, v_cod)), 0) INTO v_salas_fn
      FROM sala AS s;

    IF v_dep <> 0 OR v_salas <> v_salas_fn OR v_total <> 0 THEN
        RAISE EXCEPTION 'Vino C sin stock: vista (dep=%, salas=%, total=%) y fn_stock_sala=%',
            v_dep, v_salas, v_total, v_salas_fn;
    END IF;

    RAISE NOTICE 'OK A2: vw_stock_total_vino coincide con stock_deposito y fn_stock_sala';
END $$;

-- -----------------------------------------------------------------------------
-- A3. vw_ventas_mensuales_sala coincide con fn_total_comprobante, con
--     comprobante.total y con el cálculo manual; agrupa por sala y por mes.
--     Marzo: 6300 (3000 + 4000 brutos, 700 de descuento) y 5 botellas.
--     Abril: 1800 (2000 brutos, 200 de descuento) y 1 botella.
--     La sala 9002 no tiene ventas: no debe aparecer.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_fn_subtotal numeric(12,2);
    v_fn_desc     numeric(12,2);
    v_fn_total    numeric(12,2);
    v_cab_total   numeric(12,2);
    v_monto       numeric(12,2);
    v_botellas    bigint;
    v_comprobantes bigint;
BEGIN
    SELECT subtotal, descuento, total
      INTO v_fn_subtotal, v_fn_desc, v_fn_total
      FROM fn_total_comprobante(9001);

    SELECT total INTO v_cab_total
      FROM comprobante
     WHERE nro_comprobante = 9001;

    IF v_fn_subtotal <> 7000.00 OR v_fn_desc <> 700.00 OR v_fn_total <> 6300.00 THEN
        RAISE EXCEPTION 'fn_total_comprobante(9001) inesperado: (%, %, %)',
            v_fn_subtotal, v_fn_desc, v_fn_total;
    END IF;

    IF v_cab_total <> v_fn_total THEN
        RAISE EXCEPTION 'comprobante.total (%) difiere de fn_total_comprobante (%)',
            v_cab_total, v_fn_total;
    END IF;

    SELECT monto_total, botellas_vendidas, comprobantes
      INTO v_monto, v_botellas, v_comprobantes
      FROM vw_ventas_mensuales_sala
     WHERE id_sala = 9001
       AND mes = DATE '2026-03-01';

    IF v_monto IS NULL THEN
        RAISE EXCEPTION 'vw_ventas_mensuales_sala no devolvió la fila de marzo de la sala 9001';
    END IF;

    IF v_monto <> v_fn_total OR v_monto <> v_cab_total THEN
        RAISE EXCEPTION 'Marzo: vista=%, fn_total_comprobante=%, cabecera=%',
            v_monto, v_fn_total, v_cab_total;
    END IF;

    IF v_monto <> 6300.00 OR v_botellas <> 5 OR v_comprobantes <> 1 THEN
        RAISE EXCEPTION 'Marzo: se esperaban (6300.00, 5, 1) y se obtuvo (%, %, %)',
            v_monto, v_botellas, v_comprobantes;
    END IF;

    SELECT monto_total, botellas_vendidas, comprobantes
      INTO v_monto, v_botellas, v_comprobantes
      FROM vw_ventas_mensuales_sala
     WHERE id_sala = 9001
       AND mes = DATE '2026-04-01';

    IF v_monto IS NULL THEN
        RAISE EXCEPTION 'vw_ventas_mensuales_sala no devolvió la fila de abril de la sala 9001';
    END IF;

    IF v_monto <> 1800.00 OR v_botellas <> 1 OR v_comprobantes <> 1 THEN
        RAISE EXCEPTION 'Abril: se esperaban (1800.00, 1, 1) y se obtuvo (%, %, %)',
            v_monto, v_botellas, v_comprobantes;
    END IF;

    -- Cross-check del comprobante 9002 (abril) contra la función y la cabecera:
    -- cierra sobre el segundo mes la misma propiedad que marzo prueba sobre 9001.
    SELECT subtotal, descuento, total
      INTO v_fn_subtotal, v_fn_desc, v_fn_total
      FROM fn_total_comprobante(9002);

    SELECT total INTO v_cab_total
      FROM comprobante
     WHERE nro_comprobante = 9002;

    IF v_fn_subtotal <> 2000.00 OR v_fn_desc <> 200.00 OR v_fn_total <> 1800.00 THEN
        RAISE EXCEPTION 'fn_total_comprobante(9002) inesperado: (%, %, %)',
            v_fn_subtotal, v_fn_desc, v_fn_total;
    END IF;

    IF v_cab_total <> v_fn_total OR v_monto <> v_fn_total THEN
        RAISE EXCEPTION 'Abril: vista=%, fn_total_comprobante=%, cabecera=%',
            v_monto, v_fn_total, v_cab_total;
    END IF;

    IF EXISTS (SELECT 1 FROM vw_ventas_mensuales_sala WHERE id_sala = 9002) THEN
        RAISE EXCEPTION 'La sala 9002 no tiene ventas y aparece en vw_ventas_mensuales_sala';
    END IF;

    RAISE NOTICE 'OK A3: vw_ventas_mensuales_sala coincide con fn_total_comprobante y comprobante.total';
END $$;

-- -----------------------------------------------------------------------------
-- A4. vw_documentos_pendientes = documentos no procesados.
--     Pendientes: ingresos 9001 y 9002; transferencias 9001 y 9002.
--     Excluidos: 9003 (procesado) en ambos tipos.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_n      integer;
    v_ref    text;
    v_estado estado_documento;
    v_sala   integer;
BEGIN
    SELECT count(*) INTO v_n
      FROM vw_documentos_pendientes
     WHERE numero BETWEEN 9001 AND 9003;

    IF v_n <> 4 THEN
        RAISE EXCEPTION 'Se esperaban 4 documentos pendientes y hay %', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM vw_documentos_pendientes
     WHERE tipo_documento = 'ingreso' AND numero IN (9001, 9002);

    IF v_n <> 2 THEN
        RAISE EXCEPTION 'Se esperaban 2 ingresos pendientes y hay %', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM vw_documentos_pendientes
     WHERE tipo_documento = 'transferencia' AND numero IN (9001, 9002);

    IF v_n <> 2 THEN
        RAISE EXCEPTION 'Se esperaban 2 transferencias pendientes y hay %', v_n;
    END IF;

    -- El documento procesado no debe aparecer, ni ningún estado fuera del par
    -- que el contrato considera pendiente.
    SELECT count(*) INTO v_n
      FROM vw_documentos_pendientes
     WHERE numero BETWEEN 9001 AND 9003
       AND estado NOT IN ('en_confeccion', 'terminado');

    IF v_n <> 0 THEN
        RAISE EXCEPTION 'vw_documentos_pendientes expone % filas con estado no pendiente', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM vw_documentos_pendientes
     WHERE numero = 9003;

    IF v_n <> 0 THEN
        RAISE EXCEPTION 'El documento 9003 (procesado) aparece % veces en vw_documentos_pendientes', v_n;
    END IF;

    -- Referencia y estado de un ingreso y de una transferencia.
    SELECT referencia, id_sala, estado
      INTO v_ref, v_sala, v_estado
      FROM vw_documentos_pendientes
     WHERE tipo_documento = 'ingreso' AND numero = 9001;

    IF v_ref IS DISTINCT FROM 'Bodega Test 006' OR v_sala IS NOT NULL OR v_estado IS DISTINCT FROM 'en_confeccion' THEN
        RAISE EXCEPTION 'Ingreso 9001: referencia=%, id_sala=%, estado=%',
            v_ref, v_sala, v_estado;
    END IF;

    SELECT referencia, id_sala, estado
      INTO v_ref, v_sala, v_estado
      FROM vw_documentos_pendientes
     WHERE tipo_documento = 'transferencia' AND numero = 9001;

    IF v_ref IS DISTINCT FROM 'Localidad Test 006' OR v_sala IS DISTINCT FROM 9001 OR v_estado IS DISTINCT FROM 'en_confeccion' THEN
        RAISE EXCEPTION 'Transferencia 9001: referencia=%, id_sala=%, estado=%',
            v_ref, v_sala, v_estado;
    END IF;

    RAISE NOTICE 'OK A4: vw_documentos_pendientes excluye los procesados y conserva la referencia';
END $$;

-- -----------------------------------------------------------------------------
-- A5. vw_ficha_vino: stock coherente con vw_stock_total_vino, composición y
--     maridajes en JSONB; arreglos vacíos cuando no hay filas.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_cod_a       integer;
    v_cod_c       integer;
    v_stock_total integer;
    v_stock_dep   integer;
    v_stock_salas integer;
    v_composicion jsonb;
    v_maridajes   jsonb;
    v_suma        numeric(5,2);
    v_n           integer;
BEGIN
    SELECT cod_vino INTO v_cod_a FROM vino WHERE nombre_comercial = 'Vino Test 006 A';

    SELECT stock_total, stock_deposito, stock_salas, composicion, maridajes
      INTO v_stock_total, v_stock_dep, v_stock_salas, v_composicion, v_maridajes
      FROM vw_ficha_vino
     WHERE cod_vino = v_cod_a;

    IF v_stock_total IS NULL THEN
        RAISE EXCEPTION 'vw_ficha_vino no devolvió fila para el vino A';
    END IF;

    IF v_stock_total <> 112 OR v_stock_dep <> 100 OR v_stock_salas <> 12 THEN
        RAISE EXCEPTION 'Vino A: ficha (total=%, dep=%, salas=%) y se esperaba (112, 100, 12)',
            v_stock_total, v_stock_dep, v_stock_salas;
    END IF;

    IF jsonb_array_length(v_composicion) <> 2 THEN
        RAISE EXCEPTION 'Vino A: se esperaban 2 cepas y hay %',
            jsonb_array_length(v_composicion);
    END IF;

    -- ORDER BY porcentaje DESC, nombre: Malbec (60) primero.
    IF v_composicion -> 0 ->> 'nombre' <> 'Malbec Test 006' THEN
        RAISE EXCEPTION 'Vino A: primera cepa inesperada (%)',
            v_composicion -> 0 ->> 'nombre';
    END IF;

    SELECT COALESCE(SUM((e ->> 'porcentaje')::numeric), 0) INTO v_suma
      FROM jsonb_array_elements(v_composicion) AS e;

    IF v_suma <> 100.00 THEN
        RAISE EXCEPTION 'Vino A: la composición de la ficha suma %', v_suma;
    END IF;

    IF jsonb_array_length(v_maridajes) <> 1
       OR v_maridajes -> 0 ->> 'nombre' <> 'Carnes Test 006'
       OR (v_maridajes -> 0 ->> 'temperatura_servicio')::numeric <> 18.0 THEN
        RAISE EXCEPTION 'Vino A: maridajes inesperados (%)', v_maridajes;
    END IF;

    -- Vino C: sin stock, sin composición y sin maridajes.
    SELECT cod_vino INTO v_cod_c FROM vino WHERE nombre_comercial = 'Vino Test 006 C';

    SELECT stock_total, composicion, maridajes
      INTO v_stock_total, v_composicion, v_maridajes
      FROM vw_ficha_vino
     WHERE cod_vino = v_cod_c;

    IF v_stock_total IS NULL OR v_stock_total <> 0 THEN
        RAISE EXCEPTION 'Vino C sin stock: ficha.stock_total = %', v_stock_total;
    END IF;

    IF v_composicion <> '[]'::jsonb OR v_maridajes <> '[]'::jsonb THEN
        RAISE EXCEPTION 'Vino C: se esperaban arreglos vacíos y se obtuvo composición=% maridajes=%',
            v_composicion, v_maridajes;
    END IF;

    -- Coherencia global: la ficha no puede diferir de vw_stock_total_vino.
    SELECT count(*) INTO v_n
      FROM vw_ficha_vino AS f
      JOIN vw_stock_total_vino AS s USING (cod_vino)
     WHERE f.stock_total   <> s.stock_total
        OR f.stock_deposito <> s.stock_deposito
        OR f.stock_salas    <> s.stock_salas;

    IF v_n <> 0 THEN
        RAISE EXCEPTION 'vw_ficha_vino difiere de vw_stock_total_vino en % filas', v_n;
    END IF;

    RAISE NOTICE 'OK A5: vw_ficha_vino es coherente con vw_stock_total_vino y con RN-05';
END $$;

-- -----------------------------------------------------------------------------
-- A6. vw_ventas_mensuales_sala: el bucket mensual es independiente del
--     TimeZone de la sesión (R-015) y su contrato de columnas no cambió.
--     Los comprobantes 9001 (marzo) y 9002 (abril) son el fixture de dos
--     meses distintos ya sembrado por el camino normal de escritura.
--     La vista usa date_trunc('month', v.fecha::timestamp)::date; sin el
--     cast explícito, PostgreSQL resolvería date_trunc con timestamptz según
--     el huso de la sesión (latente, aunque el truncado al mes es estable).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    c_zonas   text[] := ARRAY[
        'America/Argentina/Buenos_Aires',
        'Pacific/Kiritimati',
        'America/Santiago'];
    v_prev    text := current_setting('TimeZone');
    v_zona    text;
    v_ref     text;
    v_obs     text;
    v_meses   date[];
    v_columnas text[];
    v_esperadas text[] := ARRAY[
        'id_sala:integer',
        'id_localidad:integer',
        'localidad:character varying',
        'mes:date',
        'botellas_vendidas:numeric',
        'monto_total:numeric',
        'comprobantes:bigint'];
    v_dia     integer;
BEGIN
    -- Contrato de columnas, orden y tipos: la API depende de él.
    SELECT array_agg(column_name || ':' || data_type
                     ORDER BY ordinal_position)
      INTO v_columnas
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'vw_ventas_mensuales_sala';

    IF v_columnas IS DISTINCT FROM v_esperadas THEN
        RAISE EXCEPTION 'Contrato de vw_ventas_mensuales_sala cambiado: % (esperado %)',
            v_columnas, v_esperadas;
    END IF;

    -- Ningún mes puede salir con día distinto del 1.
    FOR v_dia IN
        SELECT DISTINCT EXTRACT(DAY FROM mes)::integer
          FROM vw_ventas_mensuales_sala
         WHERE id_sala = 9001
    LOOP
        IF v_dia <> 1 THEN
            RAISE EXCEPTION 'vw_ventas_mensuales_sala devolvió un mes con día %', v_dia;
        END IF;
    END LOOP;

    -- Referencia: filas (mes, monto, botellas, comprobantes) de la sala 9001.
    PERFORM set_config('TimeZone', c_zonas[1], true);

    SELECT string_agg(
               mes::text || '|' || monto_total::text || '|' ||
               botellas_vendidas::text || '|' || comprobantes::text,
               ',' ORDER BY mes)
      INTO v_ref
      FROM vw_ventas_mensuales_sala
     WHERE id_sala = 9001;

    SELECT array_agg(mes ORDER BY mes)
      INTO v_meses
      FROM vw_ventas_mensuales_sala
     WHERE id_sala = 9001;

    IF v_ref IS NULL THEN
        RAISE EXCEPTION 'vw_ventas_mensuales_sala no devolvió filas para la sala 9001';
    END IF;

    IF v_meses IS DISTINCT FROM ARRAY[DATE '2026-03-01', DATE '2026-04-01'] THEN
        RAISE EXCEPTION 'Meses esperados {2026-03-01, 2026-04-01} y se obtuvo %', v_meses;
    END IF;

    -- Repetir la consulta en los otros husos; el resultado debe ser idéntico.
    FOREACH v_zona IN ARRAY c_zonas LOOP
        PERFORM set_config('TimeZone', v_zona, true);

        SELECT string_agg(
                   mes::text || '|' || monto_total::text || '|' ||
                   botellas_vendidas::text || '|' || comprobantes::text,
                   ',' ORDER BY mes)
          INTO v_obs
          FROM vw_ventas_mensuales_sala
         WHERE id_sala = 9001;

        IF v_obs IS DISTINCT FROM v_ref THEN
            RAISE EXCEPTION 'TimeZone % alteró el bucket mensual: % vs %',
                v_zona, v_obs, v_ref;
        END IF;
    END LOOP;

    PERFORM set_config('TimeZone', v_prev, true);

    RAISE NOTICE 'OK A6: vw_ventas_mensuales_sala es estable en tres TimeZone y conserva su contrato';
END $$;

-- -----------------------------------------------------------------------------
-- Cierre: la prueba no deja cambios.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE 'OK: todas las aserciones de test_006_vistas pasaron';
END $$;

ROLLBACK;
