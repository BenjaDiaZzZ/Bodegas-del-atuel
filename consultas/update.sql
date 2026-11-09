-- =============================================================================
-- consultas/update.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Rol P1 · Consignas U1 a U6 de la sección 5.1 de docs/SPEC.md.
--
-- Forma de uso:
--   psql -U <usuario> -d bodegas_del_atuel -f consultas/update.sql
--
-- Cada consigna está dentro de un bloque transaccional con:
--   BEGIN; → control previo → UPDATE → control posterior → ROLLBACK;
-- El ROLLBACK es deliberado: permite verificar los cambios sin destruir el
-- dataset. Los valores literales son parámetros de ejemplo a ajustar; sin el
-- seed de la Tarea 3.3, las sentencias afectan 0 filas.
-- =============================================================================


-- =============================================================================
-- U1 · Recalcular los totales de todos los comprobantes reutilizando fn_total_comprobante.
--
-- Estrategia:
--   - Una CTE y CROSS JOIN LATERAL llaman la función para cada comprobante.
--   - Solo se actualizan filas cuyos tres importes difieren del cálculo.
-- =============================================================================
BEGIN;

-- Control previo: comprobantes con sus totales actuales.
SELECT COUNT(*) AS u1_comprobantes
FROM comprobante;

WITH calculado AS (
    SELECT c.nro_comprobante, f.subtotal, f.descuento, f.total
    FROM comprobante c
    CROSS JOIN LATERAL fn_total_comprobante(c.nro_comprobante) f
)
UPDATE comprobante c
SET subtotal = calc.subtotal,
    descuento = calc.descuento,
    total = calc.total
FROM calculado calc
WHERE calc.nro_comprobante = c.nro_comprobante
  AND (c.subtotal, c.descuento, c.total) IS DISTINCT FROM
      (calc.subtotal, calc.descuento, calc.total);

-- Control posterior: debe devolver 0.
SELECT COUNT(*) AS u1_totales_inconsistentes
FROM comprobante c
CROSS JOIN LATERAL fn_total_comprobante(c.nro_comprobante) f
WHERE (c.subtotal, c.descuento, c.total) IS DISTINCT FROM
      (f.subtotal, f.descuento, f.total);

ROLLBACK;


-- =============================================================================
-- U2 · Aumentar salarios según antigüedad con fn_antiguedad_anios.
--
-- Estrategia:
--   - La función obtiene años completos desde la fecha de ingreso.
--   - Solo los empleados con cinco años completos o más reciben el 20 %;
--     el resto queda sin cambios.
-- =============================================================================
BEGIN;

-- Control previo: situación actual, limitada a los primeros 20 CUIT.
SELECT cuit, nombre, fecha_ingreso,
       fn_antiguedad_anios(fecha_ingreso) AS antiguedad_anios,
       salario AS salario_actual
FROM empleado
ORDER BY cuit
LIMIT 20;

UPDATE empleado
SET salario = ROUND(salario * 1.20, 2)
WHERE fn_antiguedad_anios(fecha_ingreso) >= 5;

-- Control posterior: salarios nuevos y cantidad de empleados por tramo.
SELECT cuit, nombre, fecha_ingreso,
       fn_antiguedad_anios(fecha_ingreso) AS antiguedad_anios,
       salario AS salario_nuevo
FROM empleado
ORDER BY cuit
LIMIT 20;

SELECT CASE WHEN fn_antiguedad_anios(fecha_ingreso) >= 5
            THEN '5 años o más' ELSE 'menos de 5 años' END AS tramo_antiguedad,
       COUNT(*) AS empleados,
       SUM(salario) AS salarios_nuevos
FROM empleado
GROUP BY 1
ORDER BY 1;

ROLLBACK;


-- =============================================================================
-- U3 · Subir el precio de todos los vinos de una bodega (dispara RN-13).
--
-- Estrategia:
--   - El UPDATE aumenta 13 % y el trigger registra cada cambio real.
--   - app.usuario se establece dentro de la transacción para identificar al autor.
-- =============================================================================
BEGIN;

-- Control previo: vinos de la bodega y auditorías existentes.
SELECT COUNT(*) AS u3_vinos_bodega
FROM vino
WHERE cuit_bodega = (SELECT cuit FROM bodega ORDER BY cuit LIMIT 1); -- reemplazar por un CUIT existente en el dataset

SELECT COUNT(*) AS u3_filas_auditoria
FROM auditoria_precio;

SELECT set_config('app.usuario', 'consulta_u3', true);

UPDATE vino
SET precio_venta = ROUND(precio_venta * 1.13, 2)
WHERE cuit_bodega = (SELECT cuit FROM bodega ORDER BY cuit LIMIT 1); -- reemplazar por un CUIT existente en el dataset

-- Control posterior: el aumento de auditorías debe igualar las filas afectadas.
SELECT COUNT(*) AS u3_vinos_bodega
FROM vino
WHERE cuit_bodega = (SELECT cuit FROM bodega ORDER BY cuit LIMIT 1);

SELECT COUNT(*) AS u3_filas_auditoria
FROM auditoria_precio;

SELECT cod_vino, precio_anterior, precio_nuevo, usuario
FROM auditoria_precio
ORDER BY id_auditoria DESC
LIMIT 20;

ROLLBACK;


-- =============================================================================
-- U4 · Intercambiar el día de cierre lunes ↔ miércoles en una sola sentencia.
--
-- Estrategia:
--   - Un CASE mapea lunes (1) a miércoles (3) y miércoles (3) a lunes (1).
-- =============================================================================
BEGIN;

-- Control previo: distribución por día de cierre.
SELECT dia_cierre_semanal, COUNT(*)
FROM sala
GROUP BY 1
ORDER BY 1;

UPDATE sala
SET dia_cierre_semanal = CASE dia_cierre_semanal
    WHEN 1 THEN 3
    WHEN 3 THEN 1
    ELSE dia_cierre_semanal
END
WHERE dia_cierre_semanal IN (1, 3);

-- Control posterior: distribución intercambiada.
SELECT dia_cierre_semanal, COUNT(*)
FROM sala
GROUP BY 1
ORDER BY 1;

ROLLBACK;


-- =============================================================================
-- U5 · Aplicar 15 % de descuento a los 10 vinos menos vendidos.
--
-- Estrategia:
--   - Una subconsulta agrupa las unidades vendidas, incluyendo vinos sin ventas,
--     y desempata por cod_vino para seleccionar hasta 10 vinos.
--   - El precio resultante debe seguir siendo mayor que cero por ck_vino_precio_venta.
-- =============================================================================
BEGIN;

-- Control previo: diez vinos con menos unidades vendidas y precio actual.
SELECT v.cod_vino, v.nombre_comercial,
       COALESCE(SUM(rc.cantidad), 0) AS unidades_vendidas,
       v.precio_venta AS precio_actual
FROM vino v
LEFT JOIN renglon_comprobante rc ON rc.cod_vino = v.cod_vino
GROUP BY v.cod_vino, v.nombre_comercial, v.precio_venta
ORDER BY COALESCE(SUM(rc.cantidad), 0) ASC, v.cod_vino
LIMIT 10;

UPDATE vino
SET precio_venta = ROUND(precio_venta * 0.85, 2)
WHERE cod_vino IN (
    SELECT v.cod_vino
    FROM vino v
    LEFT JOIN renglon_comprobante rc ON rc.cod_vino = v.cod_vino
    GROUP BY v.cod_vino
    ORDER BY COALESCE(SUM(rc.cantidad), 0) ASC, v.cod_vino
    LIMIT 10
);

-- Control posterior: los mismos diez vinos con el precio actualizado.
SELECT v.cod_vino, v.nombre_comercial,
       COALESCE(SUM(rc.cantidad), 0) AS unidades_vendidas,
       v.precio_venta AS precio_nuevo
FROM vino v
LEFT JOIN renglon_comprobante rc ON rc.cod_vino = v.cod_vino
GROUP BY v.cod_vino, v.nombre_comercial, v.precio_venta
ORDER BY COALESCE(SUM(rc.cantidad), 0) ASC, v.cod_vino
LIMIT 10;

ROLLBACK;


-- =============================================================================
-- U6 · Prorrogar un año los permisos de los exportadores con más de 3 permisos.
--
-- Estrategia:
--   - La subconsulta agrupa permiso_exportacion y filtra con HAVING COUNT(*) > 3;
--     la FK de permisos ya garantiza que sean exportadores.
--   - Decisión del equipo: en lugar de subir el descuento al 35 % (consigna del
--     PDF), se prorroga un año el vencimiento. cliente.descuento es GENERATED
--     ALWAYS (R-002) y no admite UPDATE; cambiarlo exigiría un cambio de esquema
--     que el equipo descartó.
--   - El nuevo vencimiento sigue cumpliendo ck_permiso_fechas (vencimiento
--     posterior a la emisión).
-- =============================================================================
BEGIN;

-- Control previo: exportadores con más de tres permisos y vencimientos actuales.
SELECT p.id_cliente, p.cod_permiso, p.fecha_vencimiento
FROM permiso_exportacion p
WHERE p.id_cliente IN (
    SELECT pe.id_cliente
    FROM permiso_exportacion pe
    GROUP BY pe.id_cliente
    HAVING COUNT(*) > 3
)
ORDER BY p.id_cliente, p.cod_permiso;

UPDATE permiso_exportacion p
SET fecha_vencimiento = (p.fecha_vencimiento + INTERVAL '1 year')::date
WHERE p.id_cliente IN (
    SELECT pe.id_cliente
    FROM permiso_exportacion pe
    GROUP BY pe.id_cliente
    HAVING COUNT(*) > 3
);

-- Control posterior: mismos permisos con las nuevas fechas de vencimiento.
SELECT p.id_cliente, p.cod_permiso, p.fecha_vencimiento
FROM permiso_exportacion p
WHERE p.id_cliente IN (
    SELECT pe.id_cliente
    FROM permiso_exportacion pe
    GROUP BY pe.id_cliente
    HAVING COUNT(*) > 3
)
ORDER BY p.id_cliente, p.cod_permiso;

ROLLBACK;
