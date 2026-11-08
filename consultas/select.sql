-- =============================================================================
-- consultas/select.sql · TPI «Bodegas del Atuel»
-- Consultas SELECT de la Sección 8 (Tarea 5.4 — P2).
-- S1, S4, S8 y S10 se usan como referencia de benchmark para Fase 4 (índices).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- S1 · Total de ventas por sala y mes
-- Tablas: comprobante, renglon_comprobante
-- -----------------------------------------------------------------------------
SELECT s.id_sala,
       date_trunc('month', c.fecha) AS mes,
       COUNT(DISTINCT c.nro_comprobante) AS comprobantes,
       SUM(rc.subtotal) AS ingresos_netos,
       SUM(rc.descuento) AS descuentos
  FROM comprobante c
  JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
  JOIN sala s ON s.id_sala = c.id_sala
 GROUP BY s.id_sala, date_trunc('month', c.fecha)
 ORDER BY s.id_sala, mes;

-- -----------------------------------------------------------------------------
-- S4 · Ranking de vinos más vendidos por volumen
-- Tablas: renglon_comprobante, vino
-- -----------------------------------------------------------------------------
SELECT v.cod_vino,
       v.nombre_comercial,
       v.tipo,
       SUM(rc.cantidad) AS unidades_vendidas,
       SUM(rc.subtotal) AS ingresos
  FROM renglon_comprobante rc
  JOIN vino v ON v.cod_vino = rc.cod_vino
 GROUP BY v.cod_vino, v.nombre_comercial, v.tipo
 ORDER BY unidades_vendidas DESC
 LIMIT 20;

-- -----------------------------------------------------------------------------
-- S8 · Estado actual de stock por sala (salas con vino faltante)
-- Tablas: stock_sala, sala, vino
-- -----------------------------------------------------------------------------
SELECT s.id_sala,
       s.direccion,
       COUNT(*) AS vinos_con_stock,
       SUM(ss.cantidad) AS botellas_totales,
       COUNT(*) FILTER (WHERE ss.cantidad = 0) AS vinos_agotados
  FROM stock_sala ss
  JOIN sala s ON s.id_sala = ss.id_sala
  JOIN vino v ON v.cod_vino = ss.cod_vino
 GROUP BY s.id_sala, s.direccion
HAVING COUNT(*) FILTER (WHERE ss.cantidad = 0) > 0
 ORDER BY vinos_agotados DESC;

-- -----------------------------------------------------------------------------
-- S10 · Clientes con compras superiores al promedio de su localidad (CTE + correlacionada)
-- Tablas: comprobante, cliente, localidad
-- -----------------------------------------------------------------------------
WITH ventas_por_cliente AS (
    SELECT cb.id_cliente,
           cl.nombre,
           cl.id_localidad,
           SUM(cb.total) AS total_compras,
           COUNT(*) AS n_compras
      FROM comprobante cb
      JOIN cliente cl ON cl.id_cliente = cb.id_cliente
      GROUP BY cb.id_cliente, cl.nombre, cl.id_localidad
),
promedio_localidad AS (
    SELECT vpc.id_localidad,
           AVG(vpc.total_compras) AS promedio
      FROM ventas_por_cliente vpc
     GROUP BY vpc.id_localidad
)
SELECT vpc.nombre,
       l.nombre AS localidad,
       vpc.total_compras,
       vpc.n_compras,
       pl.promedio AS promedio_localidad
  FROM ventas_por_cliente vpc
  JOIN localidad l ON l.id_localidad = vpc.id_localidad
  JOIN promedio_localidad pl ON pl.id_localidad = vpc.id_localidad
 WHERE vpc.total_compras > (
         SELECT AVG(v2.total_compras)
           FROM ventas_por_cliente v2
          WHERE v2.id_localidad = vpc.id_localidad
       )
 ORDER BY vpc.total_compras DESC;
