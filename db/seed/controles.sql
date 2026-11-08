-- =============================================================================
-- controles.sql · TPI «Bodegas del Atuel»
-- Consultas de verificación posteriores a la carga masiva (Tarea 3.6).
-- Ejecutar después de seed.py con: psql -f db/seed/controles.sql
-- =============================================================================

-- 1. Conteo por tabla
SELECT 'localidad' AS tabla, count(*) AS filas FROM localidad
UNION ALL SELECT 'cepa', count(*) FROM cepa
UNION ALL SELECT 'maridaje', count(*) FROM maridaje
UNION ALL SELECT 'bodega', count(*) FROM bodega
UNION ALL SELECT 'transportista', count(*) FROM transportista
UNION ALL SELECT 'finca', count(*) FROM finca
UNION ALL SELECT 'sala', count(*) FROM sala
UNION ALL SELECT 'empleado', count(*) FROM empleado
UNION ALL SELECT 'parcela', count(*) FROM parcela
UNION ALL SELECT 'vino', count(*) FROM vino
UNION ALL SELECT 'cliente', count(*) FROM cliente
UNION ALL SELECT 'lote_uva', count(*) FROM lote_uva
UNION ALL SELECT 'composicion', count(*) FROM composicion
UNION ALL SELECT 'vino_maridaje', count(*) FROM vino_maridaje
UNION ALL SELECT 'socio', count(*) FROM socio
UNION ALL SELECT 'distribuidor', count(*) FROM distribuidor
UNION ALL SELECT 'exportador', count(*) FROM exportador
UNION ALL SELECT 'permiso_exportacion', count(*) FROM permiso_exportacion
UNION ALL SELECT 'transportista_localidad', count(*) FROM transportista_localidad
UNION ALL SELECT 'analisis_calidad', count(*) FROM analisis_calidad
UNION ALL SELECT 'comprobante', count(*) FROM comprobante
UNION ALL SELECT 'renglon_comprobante', count(*) FROM renglon_comprobante
UNION ALL SELECT 'ingreso', count(*) FROM ingreso
UNION ALL SELECT 'renglon_ingreso', count(*) FROM renglon_ingreso
UNION ALL SELECT 'transferencia', count(*) FROM transferencia
UNION ALL SELECT 'renglon_transferencia', count(*) FROM renglon_transferencia
UNION ALL SELECT 'stock_deposito', count(*) FROM stock_deposito
UNION ALL SELECT 'stock_sala', count(*) FROM stock_sala;

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

-- Resultado: todas las consultas deben devolver 0 errores (salvo la 1, que es informativa).
