-- =============================================================================
-- 008_indices.sql · TPI «Bodegas del Atuel»
-- Índices secundarios para consultas de la Sección 8 (Tarea 4.2).
-- Aplicar DESPUÉS de 001-007 y de la carga del seed. Correr ANALYZE después.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. COMPUESTO · Ventas por sala y rango de fechas
-- Justificación: S1 agrupa por id_sala y filtra/ordena por fecha. El orden
-- (igualdad primero, rango después) permite Index Scan y evita el Sort
-- en disco que aparece con Seq Scan sobre 350k renglones.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_comprobante_sala_fecha
    ON comprobante (id_sala, fecha);

-- -----------------------------------------------------------------------------
-- 2. PARCIAL · Transferencias no procesadas
-- Justificación: la mayoría de transferencias quedan en 'procesado'. Filtrar
-- solo las pendientes con WHERE selectivo reduce el tamaño del índice y
-- mejora la búsqueda de transferencias activas.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_transferencia_no_procesadas
    ON transferencia (id_sala, fecha_confeccion)
    WHERE estado <> 'procesado';

-- -----------------------------------------------------------------------------
-- 3. FK no-PK · Renglones de comprobante por vino
-- Justificación: PostgreSQL NO indexa automáticamente el lado hijo de una
-- FK. S4 agrupa renglon_comprobante por cod_vino; sin este índice cada
-- consulta hace Seq Scan sobre 350k filas. INCLUDE cubre las columnas
-- agregadas para habilitar Index-Only Scan.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_renglon_comprobante_vino
    ON renglon_comprobante (cod_vino)
    INCLUDE (cantidad, subtotal, descuento);

-- -----------------------------------------------------------------------------
-- 3b. FK no-PK · Renglones por comprobante (join en S1)
-- Justificación: S1 hace JOIN renglon_comprobante ON nro_comprobante. Sin
-- este índice cada fila de comprobante busca en las 350k de renglones.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_renglon_comprobante_nro
    ON renglon_comprobante (nro_comprobante);

-- -----------------------------------------------------------------------------
-- 4. COVERING con INCLUDE · Totales por cliente (Index-Only Scan)
-- Justificación: S10 agrega SUM(total) GROUP BY id_cliente. Al incluir
-- total en el índice, el planificador puede hacer Index-Only Scan sin
-- acceder al heap.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_comprobante_cliente_total
    ON comprobante (id_cliente, fecha)
    INCLUDE (total);

-- -----------------------------------------------------------------------------
-- 5. BRIN · Rango de fechas en comprobante
-- Justificación: las fechas están correlacionadas con la inserción (ID
-- creciente → fecha creciente). BRIN es extremadamente compacto para
-- filtrar por rango de fechas en tablas grandes ordenadas naturalmente.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_comprobante_fecha_brin
    ON comprobante USING brin (fecha);

-- -----------------------------------------------------------------------------
-- 6. COMPUESTO · Stock de sala por vino (FK + filtro de faltantes)
-- Justificación: S8 cuenta stock_sala WHERE cantidad = 0. El índice compuesto
-- cubre la consulta con Index-Only Scan sobre (id_sala, cod_vino, cantidad).
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_stock_sala_sala_cantidad
    ON stock_sala (id_sala, cantidad)
    INCLUDE (cod_vino);

COMMIT;

-- Actualizar estadísticas para que el planificador use los índices
ANALYZE;
