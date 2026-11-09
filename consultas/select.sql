-- ============================================================================
-- consultas/select.sql · TPI «Bodegas del Atuel»
-- Consultas SELECT de la Sección 8 (Tareas 5.4 y 5.5 — P2).
-- S1, S4, S8 y S10 se usan como referencia de benchmark para Fase 4 (índices).
-- S2, S3, S5, S6, S7: integradas desde P4 (Tarea 5.5).
-- ============================================================================

-- ============================================================================
-- Código: S1
-- Enunciado: Total de ventas por sala y mes (ingresos netos y descuentos).
-- Estrategia: JOIN comprobante × renglon_comprobante × sala, GROUP BY sala y mes.
-- Parámetros modificables: date_trunc('month', ...) — cambiar 'month' por 'week' o 'year'.
-- ============================================================================
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

-- ============================================================================
-- Código: S2
-- Enunciado: Clientes con mayor facturación en los últimos 12 meses.
-- Estrategia: JOIN comprobante × cliente, filtro por fecha relativa, GROUP BY cliente.
-- Parámetros modificables: INTERVAL '12 months' — cambiar por otro rango.
-- ============================================================================
SELECT cl.id_cliente,
       cl.nombre,
       cl.tipo,
       COUNT(*) AS n_comprobantes,
       SUM(cb.total) AS facturacion_total
  FROM comprobante cb
  JOIN cliente cl ON cl.id_cliente = cb.id_cliente
 WHERE cb.fecha >= CURRENT_DATE - INTERVAL '12 months'
 GROUP BY cl.id_cliente, cl.nombre, cl.tipo
 ORDER BY facturacion_total DESC
 LIMIT 20;

-- ============================================================================
-- Código: S3
-- Enunciado: Vinos con menor rotación (sin ventas en los últimos 6 meses).
-- Estrategia: LEFT JOIN vino × renglon_comprobante × comprobante, filtro anti-join.
-- Parámetros modificables: INTERVAL '6 months' — cambiar el período de rotación.
-- ============================================================================
SELECT v.cod_vino,
       v.nombre_comercial,
       v.tipo,
       v.precio_venta
  FROM vino v
 WHERE NOT EXISTS (
         SELECT 1
           FROM renglon_comprobante rc
           JOIN comprobante cb ON cb.nro_comprobante = rc.nro_comprobante
          WHERE rc.cod_vino = v.cod_vino
            AND cb.fecha >= CURRENT_DATE - INTERVAL '6 months'
       )
 ORDER BY v.precio_venta DESC;

-- ============================================================================
-- Código: S4
-- Enunciado: Ranking de vinos más vendidos por volumen (unidades e ingresos).
-- Estrategia: JOIN renglon_comprobante × vino, GROUP BY vino, ORDER BY volumen DESC.
-- Parámetros modificables: LIMIT 20 — cambiar la cantidad de posiciones.
-- ============================================================================
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

-- ============================================================================
-- Código: S5
-- Enunciado: Distribución de ventas por tipo de cliente (socio, distribuidor, exportador).
-- Estrategia: JOIN comprobante × cliente, GROUP BY tipo, con porcentaje del total.
-- Parámetros modificables: ninguno — agrega sobre todo el dataset.
-- ============================================================================
SELECT cl.tipo AS tipo_cliente,
       COUNT(*) AS n_comprobantes,
       SUM(cb.total) AS facturacion,
       ROUND(SUM(cb.total) * 100.0 / SUM(SUM(cb.total)) OVER (), 2) AS pct_del_total
  FROM comprobante cb
  JOIN cliente cl ON cl.id_cliente = cb.id_cliente
 GROUP BY cl.tipo
 ORDER BY facturacion DESC;

-- ============================================================================
-- Código: S6
-- Enunciado: Ingresos y transferencias pendientes por sala (en_confeccion o terminado).
-- Estrategia: UNION de ingresos y transferencias no procesadas, JOIN con sala.
-- Parámetros modificables: estado IN (...) — agregar o quitar estados.
-- ============================================================================
SELECT 'ingreso' AS tipo_documento,
       i.cod_ingreso AS nro_documento,
       s.id_sala,
       s.direccion,
       i.fecha,
       i.estado
  FROM ingreso i
  JOIN transportista t ON t.id_transportista = i.id_transportista
  JOIN bodega b ON b.cuit = i.cuit_bodega
  CROSS JOIN sala s
 WHERE i.estado IN ('en_confeccion', 'terminado')
UNION ALL
SELECT 'transferencia' AS tipo_documento,
       tr.nro_solicitud,
       s.id_sala,
       s.direccion,
       tr.fecha_confeccion,
       tr.estado
  FROM transferencia tr
  JOIN sala s ON s.id_sala = tr.id_sala
 WHERE tr.estado IN ('en_confeccion', 'terminado')
 ORDER BY tipo_documento, nro_documento;

-- ============================================================================
-- Código: S7
-- Enunciado: Stock total de cada vino en depósito y en todas las salas.
-- Estrategia: FULL JOIN stock_deposito × stock_sala (agrupado por vino).
-- Parámetros modificables: ninguno — reporte de inventario completo.
-- ============================================================================
SELECT v.cod_vino,
       v.nombre_comercial,
       v.tipo,
       COALESCE(dep.deposito, 0) AS en_deposito,
       COALESCE(sal.salas, 0) AS en_salas,
       COALESCE(dep.deposito, 0) + COALESCE(sal.salas, 0) AS stock_total
  FROM vino v
  LEFT JOIN (
    SELECT cod_vino, SUM(cantidad) AS deposito
      FROM stock_deposito
     GROUP BY cod_vino
  ) dep ON dep.cod_vino = v.cod_vino
  LEFT JOIN (
    SELECT cod_vino, SUM(cantidad) AS salas
      FROM stock_sala
     GROUP BY cod_vino
  ) sal ON sal.cod_vino = v.cod_vino
 ORDER BY stock_total DESC;

-- ============================================================================
-- Código: S8
-- Enunciado: Salas con vinos agotados (cantidad = 0) y su situación de stock.
-- Estrategia: JOIN stock_sala × sala × vino, COUNT FILTER WHERE cantidad = 0.
-- Parámetros modificables: cantidad = 0 — cambiar el umbral de faltante.
-- ============================================================================
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

-- ============================================================================
-- Código: S9
-- Enunciado: Ficha integral de un vino (datos, bodega, stock, composición, maridajes).
-- Estrategia: Usa la vista vw_ficha_vino (006_vistas.sql) + JOIN con bodega y
--   STRING_AGG para las cepas y maridajes en texto legible.
-- Parámetros modificables: v.cod_vino = 1 — cambiar por otro cod_vino.
-- ============================================================================
SELECT f.cod_vino,
       f.nombre_comercial,
       f.tipo,
       f.anada,
       f.presentacion_ml,
       f.graduacion,
       f.precio_venta,
       b.razon_social AS bodega,
       b.domicilio AS bodega_domicilio,
       f.stock_deposito,
       f.stock_salas,
       f.stock_total,
       (
         SELECT STRING_AGG(ce.nombre || ' (' || co.porcentaje || '%)', ', '
                ORDER BY co.porcentaje DESC)
           FROM composicion co
           JOIN cepa ce ON ce.id_cepa = co.id_cepa
          WHERE co.cod_vino = f.cod_vino
       ) AS cepas,
       (
         SELECT STRING_AGG(m.nombre, ', ' ORDER BY m.nombre)
           FROM vino_maridaje vm
           JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
          WHERE vm.cod_vino = f.cod_vino
       ) AS maridajes,
       (
         SELECT COUNT(*) FROM renglon_comprobante rc
          WHERE rc.cod_vino = f.cod_vino
       ) AS veces_vendido
  FROM vw_ficha_vino f
  JOIN bodega b ON b.cuit = f.cuit_bodega
 WHERE f.cod_vino = 1;

-- ============================================================================
-- Código: S10
-- Enunciado: Clientes con compras superiores al promedio de su localidad.
-- Estrategia: CTE (ventas_por_cliente, promedio_localidad) + subconsulta
--   correlacionada para comparar contra el promedio local.
-- Parámetros modificables: ninguno — usa toda la tabla de comprobantes.
-- ============================================================================
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

-- ============================================================================
-- Código: S11
-- Enunciado: Ranking de vinos por facturación con acumulado y ranking por tipo.
-- Estrategia: RANK() OVER (PARTITION BY tipo ORDER BY ingresos DESC) y
--   SUM(...) OVER (PARTITION BY tipo ORDER BY ingresos DESC
--   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW).
-- Parámetros modificables: LIMIT — cambiar la cantidad de filas mostradas.
-- ============================================================================
SELECT v.cod_vino,
       v.nombre_comercial,
       v.tipo,
       SUM(rc.subtotal) AS ingresos,
       RANK() OVER (PARTITION BY v.tipo ORDER BY SUM(rc.subtotal) DESC) AS ranking_tipo,
       SUM(SUM(rc.subtotal)) OVER (
         PARTITION BY v.tipo
         ORDER BY SUM(rc.subtotal) DESC
         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS ingresos_acumulados
  FROM renglon_comprobante rc
  JOIN vino v ON v.cod_vino = rc.cod_vino
 GROUP BY v.cod_vino, v.nombre_comercial, v.tipo
 ORDER BY v.tipo, ingresos DESC;

-- ============================================================================
-- Código: S12
-- Enunciado: Vinos que fueron vendidos en TODAS las salas (división relacional).
-- Estrategia: Doble NOT EXISTS — no existe una sala donde el vino NO fue vendido.
--   Anti-join: se excluye cada par (vino, sala) que no tiene venta registrada.
-- Parámetros modificables: ninguno — división relacional completa.
-- ============================================================================
SELECT v.cod_vino,
       v.nombre_comercial,
       v.tipo
  FROM vino v
 WHERE NOT EXISTS (
         SELECT 1
           FROM sala s
          WHERE NOT EXISTS (
                  SELECT 1
                    FROM renglon_comprobante rc
                    JOIN comprobante cb ON cb.nro_comprobante = rc.nro_comprobante
                   WHERE rc.cod_vino = v.cod_vino
                     AND cb.id_sala = s.id_sala
                )
       )
 ORDER BY v.nombre_comercial;
