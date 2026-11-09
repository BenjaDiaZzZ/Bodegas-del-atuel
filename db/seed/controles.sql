-- =============================================================================
-- controles.sql · TPI «Bodegas del Atuel»
-- Consultas de verificación posteriores a la carga masiva (Tarea 3.6).
-- Ejecutar después de seed.py con: psql -f db/seed/controles.sql
-- =============================================================================

-- 1. Conteo por tabla
SELECT 'conteo:localidad' AS tabla, count(*) AS filas FROM localidad
UNION ALL SELECT 'conteo:cepa', count(*) FROM cepa
UNION ALL SELECT 'conteo:maridaje', count(*) FROM maridaje
UNION ALL SELECT 'conteo:bodega', count(*) FROM bodega
UNION ALL SELECT 'conteo:transportista', count(*) FROM transportista
UNION ALL SELECT 'conteo:finca', count(*) FROM finca
UNION ALL SELECT 'conteo:sala', count(*) FROM sala
UNION ALL SELECT 'conteo:empleado', count(*) FROM empleado
UNION ALL SELECT 'conteo:parcela', count(*) FROM parcela
UNION ALL SELECT 'conteo:vino', count(*) FROM vino
UNION ALL SELECT 'conteo:cliente', count(*) FROM cliente
UNION ALL SELECT 'conteo:lote_uva', count(*) FROM lote_uva
UNION ALL SELECT 'conteo:composicion', count(*) FROM composicion
UNION ALL SELECT 'conteo:vino_maridaje', count(*) FROM vino_maridaje
UNION ALL SELECT 'conteo:socio', count(*) FROM socio
UNION ALL SELECT 'conteo:distribuidor', count(*) FROM distribuidor
UNION ALL SELECT 'conteo:exportador', count(*) FROM exportador
UNION ALL SELECT 'conteo:permiso_exportacion', count(*) FROM permiso_exportacion
UNION ALL SELECT 'conteo:transportista_localidad', count(*) FROM transportista_localidad
UNION ALL SELECT 'conteo:analisis_calidad', count(*) FROM analisis_calidad
UNION ALL SELECT 'conteo:auditoria_precio', count(*) FROM auditoria_precio
UNION ALL SELECT 'conteo:comprobante', count(*) FROM comprobante
UNION ALL SELECT 'conteo:renglon_comprobante', count(*) FROM renglon_comprobante
UNION ALL SELECT 'conteo:ingreso', count(*) FROM ingreso
UNION ALL SELECT 'conteo:renglon_ingreso', count(*) FROM renglon_ingreso
UNION ALL SELECT 'conteo:transferencia', count(*) FROM transferencia
UNION ALL SELECT 'conteo:renglon_transferencia', count(*) FROM renglon_transferencia
UNION ALL SELECT 'conteo:stock_deposito', count(*) FROM stock_deposito
UNION ALL SELECT 'conteo:stock_sala', count(*) FROM stock_sala;

-- 2. Filas huérfanas (FK no resueltas)
SELECT 'renglon_comprobante sin comprobante' AS control, count(*) AS errores
  FROM renglon_comprobante rc LEFT JOIN comprobante c USING (nro_comprobante)
 WHERE c.nro_comprobante IS NULL
UNION ALL
SELECT 'renglon_comprobante sin vino', count(*)
  FROM renglon_comprobante rc LEFT JOIN vino v USING (cod_vino)
 WHERE v.cod_vino IS NULL
UNION ALL
SELECT 'composicion sin vino', count(*)
  FROM composicion co LEFT JOIN vino v USING (cod_vino)
 WHERE v.cod_vino IS NULL
UNION ALL
SELECT 'composicion sin cepa', count(*)
  FROM composicion co LEFT JOIN cepa ce USING (id_cepa)
 WHERE ce.id_cepa IS NULL
UNION ALL
SELECT 'sala sin localidad', count(*)
  FROM sala s LEFT JOIN localidad l USING (id_localidad)
 WHERE l.id_localidad IS NULL
UNION ALL
SELECT 'empleado sin sala', count(*)
  FROM empleado e LEFT JOIN sala s USING (id_sala)
 WHERE s.id_sala IS NULL
UNION ALL
SELECT 'stock_sala sin vino', count(*)
  FROM stock_sala ss LEFT JOIN vino v USING (cod_vino)
 WHERE v.cod_vino IS NULL;

-- 3. Stocks negativos
SELECT 'stock_sala negativo' AS control, count(*) AS errores
  FROM stock_sala WHERE cantidad < 0
UNION ALL
SELECT 'stock_deposito negativo', count(*)
  FROM stock_deposito WHERE cantidad < 0;

-- 4. Comprobantes con importe_total ≠ suma de renglones
SELECT 'comprobante con totales inconsistentes' AS control, count(*) AS errores
  FROM comprobante cb
 WHERE EXISTS (
   SELECT 1 FROM renglon_comprobante rc
    WHERE rc.nro_comprobante = cb.nro_comprobante
   HAVING COALESCE(SUM(rc.subtotal), 0) != cb.total
 );

-- 5. Vinos con suma de composición ≠ 100
SELECT 'composicion != 100' AS control, count(*) AS errores
  FROM (
    SELECT cod_vino, SUM(porcentaje) AS total
      FROM composicion
     GROUP BY cod_vino
    HAVING SUM(porcentaje) != 100
  ) sub;

-- 6. Estados inválidos
SELECT 'estado_documento inválido' AS control, count(*) AS errores
  FROM ingreso
 WHERE estado NOT IN ('en_confeccion', 'terminado', 'procesado')
UNION ALL
SELECT 'estado transferencia inválido', count(*)
  FROM transferencia
 WHERE estado NOT IN ('en_confeccion', 'terminado', 'procesado');

-- Resultado: los conteos (prefijo «conteo:») son informativos; los controles 2–6 deben devolver 0 errores.
