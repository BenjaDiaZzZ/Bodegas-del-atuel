-- =============================================================================
-- consultas/insert.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Rol P1 · Consignas I1 a I6 de la sección 5.2 de docs/SPEC.md.
--
-- Forma de uso:
--   psql -U <usuario> -d bodegas_del_atuel -f consultas/insert.sql
--
-- Cada consigna está dentro de un bloque transaccional con:
--   BEGIN; → control previo → INSERT → control posterior → ROLLBACK;
-- El ROLLBACK es deliberado: permite verificar los cambios sin destruir el
-- dataset. Los valores literales son parámetros de ejemplo a ajustar; sin el
-- seed de la Tarea 3.3, las sentencias afectan 0 filas.
-- =============================================================================


-- =============================================================================
-- I1 · Insertar la cobertura General Alvear ↔ transportista con menos envíos del último trimestre.
--
-- Estrategia:
--   - LEFT JOIN incluye transportistas sin ingresos recientes; se ordena por
--     cantidad ascendente y se desempata por id_transportista.
--   - ON CONFLICT DO NOTHING evita fallar si la cobertura ya existe.
--   - Ajustar el nombre de la localidad si el dataset lo escribe distinto.
-- =============================================================================
BEGIN;

-- Control previo: ranking de transportistas por ingresos del último trimestre.
SELECT t.id_transportista, t.razon_social, COUNT(i.cod_ingreso) AS ingresos
FROM transportista t
LEFT JOIN ingreso i
  ON i.id_transportista = t.id_transportista
 AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY t.id_transportista, t.razon_social
ORDER BY ingresos ASC, t.id_transportista;

SELECT tl.id_transportista, tl.id_localidad
FROM transportista_localidad tl
JOIN localidad l ON l.id_localidad = tl.id_localidad
WHERE l.nombre = 'General Alvear'
ORDER BY tl.id_transportista;

INSERT INTO transportista_localidad (id_transportista, id_localidad)
SELECT t.id_transportista, l.id_localidad
FROM localidad l
CROSS JOIN LATERAL (
    SELECT tr.id_transportista
    FROM transportista tr
    LEFT JOIN ingreso i
      ON i.id_transportista = tr.id_transportista
     AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
    GROUP BY tr.id_transportista
    ORDER BY COUNT(i.cod_ingreso) ASC, tr.id_transportista
    LIMIT 1
) AS t
WHERE l.nombre = 'General Alvear'
ON CONFLICT (id_transportista, id_localidad) DO NOTHING;

-- Control posterior: cobertura con transportista y localidad.
SELECT tr.razon_social, l.nombre
FROM transportista_localidad tl
JOIN transportista tr ON tr.id_transportista = tl.id_transportista
JOIN localidad l ON l.id_localidad = tl.id_localidad
WHERE l.nombre = 'General Alvear'
ORDER BY tr.id_transportista;

ROLLBACK;


-- =============================================================================
-- I2 · Crear el maridaje «cordero al disco» y asociarlo a los tintos de 14° o más.
--
-- Estrategia:
--   - EXISTS condiciona ambas sentencias; ON CONFLICT hace idempotente el alta
--     y la asociación. Temperatura de servicio de ejemplo: 18.0 °C (ajustable).
-- =============================================================================
BEGIN;

-- Control previo: cantidad de tintos con graduación mínima de 14°.
SELECT COUNT(*) AS i2_tintos_catorce_grados
FROM vino v
WHERE v.tipo = 'tinto'
  AND v.graduacion >= 14;

INSERT INTO maridaje (nombre, temperatura_servicio)
SELECT 'cordero al disco', 18.0
WHERE EXISTS (
    SELECT 1
    FROM vino v
    WHERE v.tipo = 'tinto'
      AND v.graduacion >= 14
)
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO vino_maridaje (cod_vino, id_maridaje)
SELECT v.cod_vino, m.id_maridaje
FROM vino v
CROSS JOIN maridaje m
WHERE v.tipo = 'tinto'
  AND v.graduacion >= 14
  AND m.nombre = 'cordero al disco'
ON CONFLICT (cod_vino, id_maridaje) DO NOTHING;

-- Control posterior: maridaje y cantidad de vinos elegibles asociados.
SELECT id_maridaje, nombre, temperatura_servicio
FROM maridaje
WHERE nombre = 'cordero al disco';

SELECT COUNT(*) AS i2_tintos_asociados
FROM vino v
JOIN vino_maridaje vm ON vm.cod_vino = v.cod_vino
JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
WHERE v.tipo = 'tinto'
  AND v.graduacion >= 14
  AND m.nombre = 'cordero al disco';

ROLLBACK;


-- =============================================================================
-- I3 · Crear un comprobante con 3 renglones y dejar que los triggers calculen todo.
--
-- Estrategia:
--   - El bloque usa la sala 1, elige un cliente y tres vinos con stock en orden
--     ascendente de cod_vino, respetando el orden de locks.
--   - La API/consulta envía solo (cod_vino, cantidad); los triggers completan
--     precios, descuentos, subtotales, total y descuento de stock.
-- =============================================================================
BEGIN;

-- Control previo: vinos disponibles en la sala 1.
SELECT ss.id_sala, ss.cod_vino, ss.cantidad
FROM stock_sala ss
WHERE ss.id_sala = 1
  AND ss.cantidad >= 1
ORDER BY ss.cod_vino
LIMIT 3;

SELECT COUNT(*) AS i3_comprobantes_antes
FROM comprobante;

DO $$
DECLARE
    v_cliente integer;
    v_vinos integer[];
    v_nro integer;
BEGIN
    -- cliente dado: ajustar al cliente del dataset.
    SELECT id_cliente
      INTO v_cliente
      FROM cliente
     ORDER BY id_cliente
     LIMIT 1;

    IF NOT EXISTS (SELECT 1 FROM sala WHERE id_sala = 1) THEN
        RAISE EXCEPTION 'No existe la sala con ID 1';
    END IF;

    IF v_cliente IS NULL THEN
        RAISE EXCEPTION 'No existe un cliente para el comprobante';
    END IF;

    SELECT ARRAY(
        SELECT ss.cod_vino
        FROM stock_sala ss
        WHERE ss.id_sala = 1
          AND ss.cantidad >= 1
        ORDER BY ss.cod_vino ASC
        LIMIT 3
    )
    INTO v_vinos;

    IF COALESCE(array_length(v_vinos, 1), 0) < 3 THEN
        RAISE EXCEPTION 'Se necesitan tres vinos con stock en la sala 1';
    END IF;

    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, v_cliente, 1)
    RETURNING nro_comprobante INTO v_nro;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_nro, v_vinos[1], 1),
           (v_nro, v_vinos[2], 1),
           (v_nro, v_vinos[3], 1);

    RAISE NOTICE 'Comprobante creado: %', v_nro;
END;
$$;

-- Control posterior: cabecera con importes calculados por el trigger.
SELECT nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total
FROM comprobante
ORDER BY nro_comprobante DESC
LIMIT 1;

-- Control posterior: detalle completado por el trigger de inserción.
SELECT nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal
FROM renglon_comprobante
ORDER BY nro_comprobante DESC, cod_vino ASC
LIMIT 3;

-- Control posterior: stock restante de los vinos de la venta más reciente.
SELECT ss.id_sala, ss.cod_vino, ss.cantidad
FROM stock_sala ss
WHERE (ss.id_sala, ss.cod_vino) IN (
    SELECT c.id_sala, rc.cod_vino
    FROM comprobante c
    JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
    WHERE c.nro_comprobante = (SELECT MAX(nro_comprobante) FROM comprobante)
)
ORDER BY ss.cod_vino;

ROLLBACK;


-- =============================================================================
-- I4 · Inserción simple: alta de una bodega nueva.
--
-- Estrategia:
--   - CUIT de 11 dígitos válido para cuit_dom; valores de ejemplo ajustables.
-- =============================================================================
BEGIN;

-- Control previo: verificar si el CUIT ya está usado.
SELECT COUNT(*) AS i4_bodega_existente FROM bodega WHERE cuit = '30999999999';

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30999999999', 'Bodega Nueva Consulta', 'Ruta 143 km 4');

-- Control posterior: fila insertada.
SELECT cuit, razon_social, domicilio
FROM bodega
WHERE cuit = '30999999999';

ROLLBACK;


-- =============================================================================
-- I5 · Inserción simple: alta de una sala de venta nueva.
--
-- Estrategia:
--   - Se inserta la sala con dirección, día de cierre semanal y localidad; la
--     localidad se toma del catálogo con una subconsulta y se ajusta si el
--     dataset pide otra. dia_cierre_semanal usa 1 = lunes … 7 = domingo.
-- =============================================================================
BEGIN;

-- Control previo: verificar si la dirección ya está presente.
SELECT COUNT(*) AS i5_sala_existente FROM sala WHERE direccion = 'Av. San Martín 1450';

INSERT INTO sala (direccion, dia_cierre_semanal, id_localidad)
VALUES ('Av. San Martín 1450', 2,
        (SELECT id_localidad FROM localidad ORDER BY id_localidad LIMIT 1));

-- Control posterior: fila insertada.
SELECT id_sala, direccion, dia_cierre_semanal, id_localidad FROM sala WHERE direccion = 'Av. San Martín 1450';

ROLLBACK;


-- =============================================================================
-- I6 · Crear un ingreso en confección con un renglón de 120 botellas.
--
-- Estrategia:
--   - Se elige el vino pedido y el transportista indicado como ejemplo; la
--     bodega se toma del vino para mantener coherente la FK.
--   - La cabecera nace en_confeccion (T3) para permitir insertar su renglón (T6).
-- =============================================================================
BEGIN;

-- Control previo: ingresos en confección.
SELECT COUNT(*) AS i6_ingresos_en_confeccion
FROM ingreso
WHERE estado = 'en_confeccion';

DO $$
DECLARE
    v_transportista integer;
    v_bodega cuit_dom;
    v_vino integer;
    v_cod integer;
BEGIN
    -- transportista dado: ajustar.
    SELECT id_transportista
      INTO v_transportista
      FROM transportista
     ORDER BY id_transportista
     LIMIT 1;

    -- Ajustar el nombre al vino del dataset.
    SELECT cod_vino, cuit_bodega
      INTO v_vino, v_bodega
      FROM vino
     WHERE nombre_comercial = 'Malbec Reserva'
       AND presentacion_ml = 750
     ORDER BY cod_vino
     LIMIT 1;

    IF v_transportista IS NULL THEN
        RAISE EXCEPTION 'No existe un transportista para el ingreso';
    END IF;

    IF v_vino IS NULL OR v_bodega IS NULL THEN
        RAISE EXCEPTION 'No existe el vino Malbec Reserva de 750 ml';
    END IF;

    INSERT INTO ingreso (fecha, estado, id_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 'en_confeccion', v_transportista, v_bodega)
    RETURNING cod_ingreso INTO v_cod;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_cod, v_vino, 120);

    RAISE NOTICE 'Ingreso creado: %', v_cod;
END;
$$;

-- Control posterior: ingreso y cantidad de renglones.
SELECT i.cod_ingreso, i.fecha, i.estado, i.id_transportista, i.cuit_bodega,
       COUNT(ri.cod_vino) AS cantidad_renglones,
       SUM(ri.cantidad) AS botellas
FROM ingreso i
LEFT JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
WHERE i.cod_ingreso = (SELECT MAX(cod_ingreso) FROM ingreso)
GROUP BY i.cod_ingreso, i.fecha, i.estado, i.id_transportista, i.cuit_bodega;

ROLLBACK;
