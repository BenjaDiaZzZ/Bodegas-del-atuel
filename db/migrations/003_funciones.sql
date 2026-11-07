-- =============================================================================
-- 003_funciones.sql · TPI «Bodegas del Atuel»
-- Tarea 2.2 · Funciones de negocio y consulta
--
-- Dependencias: 001_esquema.sql y 002_constraints.sql.
-- Orden: 001 → 002 → 003 → 004 → 005.
-- Alcance: funciones de solo lectura/cálculo; sin escrituras ni bloqueos.
-- =============================================================================

BEGIN;

-- RN-06: devuelve el porcentaje de descuento correspondiente al tipo de
-- cliente. Los tipos y porcentajes se fijan en docs/contratos.md §5.
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_tipo varchar)
RETURNS numeric(5,2)
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
BEGIN
    CASE p_tipo
        WHEN 'socio' THEN
            RETURN 10.00;
        WHEN 'distribuidor' THEN
            RETURN 20.00;
        WHEN 'exportador' THEN
            RETURN 30.00;
        ELSE
            RAISE EXCEPTION '[RN-06] Tipo de cliente desconocido: %', p_tipo;
    END CASE;
END;
$$;

COMMENT ON FUNCTION fn_descuento_cliente(varchar) IS
    'RN-06: devuelve el porcentaje de descuento para el tipo de cliente; IMMUTABLE y STRICT.';

-- Consulta el stock de un vino en una sala. La ausencia de fila equivale a 0;
-- el bloqueo RN-09 pertenece al trigger de venta, no a esta función STABLE.
CREATE OR REPLACE FUNCTION fn_stock_sala(p_sala integer, p_vino integer)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT ss.cantidad
            FROM stock_sala AS ss
            WHERE ss.id_sala = p_sala
              AND ss.cod_vino = p_vino
        ),
        0
    );
$$;

COMMENT ON FUNCTION fn_stock_sala(integer, integer) IS
    'Devuelve el stock del vino en la sala, o 0 si no existe una fila; STABLE y de solo lectura.';

-- Devuelve los años completos transcurridos. La fecha futura se limita a 0.
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha date)
RETURNS integer
LANGUAGE sql
STABLE
STRICT
AS $$
    SELECT GREATEST(
        0,
        EXTRACT(YEAR FROM AGE(CURRENT_DATE, p_fecha))::integer
    );
$$;

COMMENT ON FUNCTION fn_antiguedad_anios(date) IS
    'Devuelve años completos desde la fecha indicada; limita fechas futuras a 0 y es STRICT.';

-- Agrega importes de línea ya redondeados. RN-08 define subtotal de línea
-- como precio bruto menos descuento; por eso la cabecera recupera el bruto
-- sumando subtotal + descuento y deriva el descuento total como diferencia.
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro integer)
RETURNS TABLE (
    subtotal numeric(12,2),
    descuento numeric(12,2),
    total numeric(12,2)
)
LANGUAGE sql
STABLE
AS $$
    SELECT sums.subtotal,
           (sums.subtotal - sums.total)::numeric(12,2) AS descuento,
           sums.total
    FROM (
        SELECT COALESCE(SUM(rc.subtotal + rc.descuento), 0)::numeric(12,2) AS subtotal,
               COALESCE(SUM(rc.subtotal), 0)::numeric(12,2) AS total
        FROM renglon_comprobante AS rc
        WHERE rc.nro_comprobante = p_nro
    ) AS sums;
$$;

COMMENT ON FUNCTION fn_total_comprobante(integer) IS
    'Devuelve una fila con subtotal bruto, descuento derivado y total neto; suma importes de línea ya redondeados.';

COMMIT;
