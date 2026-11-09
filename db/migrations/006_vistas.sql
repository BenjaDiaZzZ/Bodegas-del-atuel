-- =============================================================================
-- 006_vistas.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Rol P3 · Vistas de reporte.
--
-- Requisito mínimo de la etapa 2: 3 vistas (una puede ser materializada).
-- Se implementan 4 vistas convencionales:
--   1. vw_stock_total_vino          → stock por vino (depósito + salas).
--   2. vw_ventas_mensuales_sala     → ventas agrupadas por sala y mes.
--   3. vw_documentos_pendientes     → ingresos y transferencias no procesados.
--   4. vw_ficha_vino                → ficha completa para S9 y la API.
--
-- Se usan vistas convencionales (no materializadas) porque el stock y las
-- ventas cambian con cada operación y el volumen del TPI no justifica el
-- costo de mantenimiento de un REFRESH MATERIALIZED VIEW. Si en la etapa 4
-- las mediciones muestran que el reporte es costoso, se puede convertir
-- vw_stock_total_vino en materializada y documentar su refresco.
--
-- Dependencias: 001_esquema.sql define la estructura (tablas y columnas), pero
-- la SEMÁNTICA de las cifras depende de 002–005:
--   · vw_ventas_mensuales_sala lee comprobante.total, que mantiene el trigger
--     RN-08 de 005. Sin 005 la vista informa 0 mientras fn_total_comprobante
--     informa el importe real (comprobado el 2026-11-07 sobre PostgreSQL 16).
--   · El stock de vw_stock_total_vino y vw_ficha_vino es el que descuentan
--     RN-09 (005) y sp_procesar_ingreso / sp_procesar_transferencia (004).
--   · La composición de vw_ficha_vino supone la suma 100 % que valida RN-05
--     (constraint trigger diferido de 005).
-- 002 agrega NOT NULL/CHECK/UNIQUE sin renombrar columnas y 003 aporta
-- fn_stock_sala y fn_total_comprobante. La coincidencia de las cuatro vistas con
-- esas funciones y con los totales mantenidos por trigger se verifica en
-- db/tests/test_006_vistas.sql.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. Stock total por vino
--    Une el stock del depósito central (1:1 con vino) con la suma de stock de
--    todas las salas. COALESCE evita NULL cuando un vino todavía no tiene
--    fila en stock_deposito o no fue distribuido a ninguna sala.
-- =============================================================================
CREATE OR REPLACE VIEW vw_stock_total_vino AS
SELECT
    v.cod_vino,
    v.nombre_comercial,
    v.tipo,
    v.anada,
    v.presentacion_ml,
    v.graduacion,
    v.precio_venta,
    v.cuit_bodega,
    b.razon_social                         AS bodega,
    COALESCE(d.cantidad, 0)                AS stock_deposito,
    COALESCE(s.cantidad, 0)                AS stock_salas,
    COALESCE(d.cantidad, 0)
        + COALESCE(s.cantidad, 0)          AS stock_total
FROM vino AS v
JOIN bodega AS b
    ON b.cuit = v.cuit_bodega
LEFT JOIN stock_deposito AS d
    ON d.cod_vino = v.cod_vino
LEFT JOIN (
    SELECT
        cod_vino,
        SUM(cantidad) AS cantidad
    FROM stock_sala
    GROUP BY cod_vino
) AS s
    ON s.cod_vino = v.cod_vino;

COMMENT ON VIEW vw_stock_total_vino IS
    'Stock total por vino: depósito central + suma de todas las salas.';


-- =============================================================================
-- 2. Ventas mensuales por sala
--    Primero agrega los renglones por comprobante para no duplicar el total
--    de la cabecera al hacer el JOIN. Después agrupa por sala y mes.
--    `monto_total` sale de comprobante.total (importe ya calculado por la
--    base, con descuento incluido); `botellas_vendidas` sale de los renglones.
--    El cast explícito `v.fecha::timestamp` fija la resolución de
--    date_trunc('month', …): sin él, PostgreSQL convierte el DATE a
--    timestamptz con el TimeZone de la sesión (pg_typeof devuelve
--    `timestamp with time zone`). El valor del bucket es el mismo en todos
--    los husos porque se trunca al mes, pero el cast elimina esa dependencia
--    latente; se verificó que el resultado es idéntico en
--    America/Argentina/Buenos_Aires, Pacific/Kiritimati y America/Santiago
--    (incluido el cambio de horario a medianoche), y la prueba A6 de
--    db/tests/test_006_vistas.sql lo vuelve a comprobar.
-- =============================================================================
CREATE OR REPLACE VIEW vw_ventas_mensuales_sala AS
WITH ventas_por_comprobante AS (
    SELECT
        c.nro_comprobante,
        c.id_sala,
        c.fecha,
        COALESCE(c.total, 0)              AS total,
        COALESCE(SUM(rc.cantidad), 0)     AS botellas
    FROM comprobante AS c
    LEFT JOIN renglon_comprobante AS rc
        ON rc.nro_comprobante = c.nro_comprobante
    WHERE c.fecha IS NOT NULL
    GROUP BY
        c.nro_comprobante,
        c.id_sala,
        c.fecha,
        c.total
)
SELECT
    v.id_sala,
    s.id_localidad,
    l.nombre                              AS localidad,
    date_trunc('month', v.fecha::timestamp)::date AS mes,
    SUM(v.botellas)                       AS botellas_vendidas,
    SUM(v.total)                          AS monto_total,
    COUNT(*)                              AS comprobantes
FROM ventas_por_comprobante AS v
JOIN sala AS s
    ON s.id_sala = v.id_sala
LEFT JOIN localidad AS l
    ON l.id_localidad = s.id_localidad
GROUP BY
    v.id_sala,
    s.id_localidad,
    l.nombre,
    date_trunc('month', v.fecha::timestamp)::date;

COMMENT ON VIEW vw_ventas_mensuales_sala IS
    'Ventas por sala y mes: botellas de los renglones y total de los comprobantes.';


-- =============================================================================
-- 3. Documentos pendientes
--    Unión de ingresos y transferencias que todavía no fueron procesados.
--    `referencia` muestra la bodega de origen (ingreso) o la localidad/sala
--    de destino (transferencia). El UNION ALL conserva ambas filas y evita
--    el costo de eliminar duplicados que no pueden existir entre tablas.
-- =============================================================================
CREATE OR REPLACE VIEW vw_documentos_pendientes AS
SELECT
    'ingreso'::text                        AS tipo_documento,
    i.cod_ingreso                          AS numero,
    i.fecha                                AS fecha,
    i.estado                               AS estado,
    NULL::integer                          AS id_sala,
    b.razon_social::text                   AS referencia
FROM ingreso AS i
JOIN bodega AS b
    ON b.cuit = i.cuit_bodega
WHERE i.estado IN ('en_confeccion', 'terminado')

UNION ALL

SELECT
    'transferencia'::text                  AS tipo_documento,
    t.nro_solicitud                        AS numero,
    t.fecha_confeccion                     AS fecha,
    t.estado                               AS estado,
    t.id_sala                              AS id_sala,
    COALESCE(l.nombre, s.direccion)::text  AS referencia
FROM transferencia AS t
JOIN sala AS s
    ON s.id_sala = t.id_sala
LEFT JOIN localidad AS l
    ON l.id_localidad = s.id_localidad
WHERE t.estado IN ('en_confeccion', 'terminado');

COMMENT ON VIEW vw_documentos_pendientes IS
    'Ingresos y transferencias en confección o terminados, pendientes de procesar.';


-- =============================================================================
-- 4. Ficha de vino
--    Reutiliza vw_stock_total_vino y agrega composición y maridajes como JSONB.
--    Evita el producto cartesiano que aparecería si se hicieran dos JOIN
--    directos contra tablas N:M en la misma consulta.
-- =============================================================================
CREATE OR REPLACE VIEW vw_ficha_vino AS
SELECT
    st.*,
    COALESCE(
        (
            SELECT jsonb_agg(
                       jsonb_build_object(
                           'id_cepa', c.id_cepa,
                           'nombre', c.nombre,
                           'porcentaje', co.porcentaje
                       )
                       ORDER BY co.porcentaje DESC, c.nombre
                   )
            FROM composicion AS co
            JOIN cepa AS c
                ON c.id_cepa = co.id_cepa
            WHERE co.cod_vino = st.cod_vino
        ),
        '[]'::jsonb
    ) AS composicion,
    COALESCE(
        (
            SELECT jsonb_agg(
                       jsonb_build_object(
                           'id_maridaje', m.id_maridaje,
                           'nombre', m.nombre,
                           'temperatura_servicio', m.temperatura_servicio
                       )
                       ORDER BY m.nombre
                   )
            FROM vino_maridaje AS vm
            JOIN maridaje AS m
                ON m.id_maridaje = vm.id_maridaje
            WHERE vm.cod_vino = st.cod_vino
        ),
        '[]'::jsonb
    ) AS maridajes
FROM vw_stock_total_vino AS st;

COMMENT ON VIEW vw_ficha_vino IS
    'Ficha completa del vino (S9): datos, bodega, stock, composición y maridajes.';

COMMIT;
