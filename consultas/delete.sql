-- =============================================================================
-- consultas/delete.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Rol P3 · Consignas D1 a D6 de la sección 8.3 del enunciado.
--
-- Forma de uso:
--   psql -U <usuario> -d bodegas_del_atuel -f consultas/delete.sql
--
-- Cada consigna está dentro de un bloque transaccional con:
--   BEGIN; → control previo → DELETE → control posterior → ROLLBACK;
-- El ROLLBACK es deliberado: el archivo se puede ejecutar para verificar
-- cuántas filas se verían afectadas sin destruir el dataset de la demo.
-- Para aplicar un borrado definitivo, cambiar el ROLLBACK final del bloque
-- por COMMIT después de revisar los conteos.
--
-- Los valores entre comillas simples (localidad, etc.) son parámetros de
-- ejemplo tomados del dataset. Ajustarlos antes de ejecutar.
-- =============================================================================


-- =============================================================================
-- D1 · Borrar los comprobantes con más de 5 años de antigüedad asociados a
--      clientes socios del club.
--
-- Estrategia:
--   - La pertenencia al subtipo se verifica con EXISTS sobre `socio`, que es
--     la tabla del subtipo (PK = FK a cliente). No se depende solo de
--     `cliente.tipo`.
--   - `renglon_comprobante` se elimina por ON DELETE CASCADE desde
--     `comprobante`; no hace falta borrar los renglones a mano.
--   - La antigüedad se calcula con CURRENT_DATE, no con una fecha fija.
-- =============================================================================
BEGIN;

-- Control previo: comprobantes que cumplen la condición.
SELECT COUNT(*) AS d1_comprobantes_a_borrar
FROM comprobante AS c
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
  AND EXISTS (
      SELECT 1
      FROM socio AS s
      WHERE s.id_cliente = c.id_cliente
  );

DELETE FROM comprobante AS c
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
  AND EXISTS (
      SELECT 1
      FROM socio AS s
      WHERE s.id_cliente = c.id_cliente
  );

-- Control posterior: debe devolver 0.
SELECT COUNT(*) AS d1_comprobantes_restantes
FROM comprobante AS c
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
  AND EXISTS (
      SELECT 1
      FROM socio AS s
      WHERE s.id_cliente = c.id_cliente
  );

ROLLBACK;


-- =============================================================================
-- D2 · Eliminar las cepas que no componen ningún vino ni están plantadas en
--      ninguna parcela.
--
-- Estrategia:
--   - Anti-join con NOT EXISTS en ambas relaciones que referencian a `cepa`
--     (`composicion` y `parcela`). Es más seguro que NOT IN cuando pudiera
--     haber NULL, y permite usar los índices de las FK.
--   - Las FK de composicion y parcela son RESTRICT, por lo que solo se pueden
--     borrar cepas realmente huérfanas.
-- =============================================================================
BEGIN;

-- Control previo: cepas huérfanas.
SELECT COUNT(*) AS d2_cepas_a_borrar
FROM cepa AS c
WHERE NOT EXISTS (
        SELECT 1
        FROM composicion AS co
        WHERE co.id_cepa = c.id_cepa
      )
  AND NOT EXISTS (
        SELECT 1
        FROM parcela AS p
        WHERE p.id_cepa = c.id_cepa
      );

DELETE FROM cepa AS c
WHERE NOT EXISTS (
        SELECT 1
        FROM composicion AS co
        WHERE co.id_cepa = c.id_cepa
      )
  AND NOT EXISTS (
        SELECT 1
        FROM parcela AS p
        WHERE p.id_cepa = c.id_cepa
      );

-- Control posterior: debe devolver 0.
SELECT COUNT(*) AS d2_cepas_restantes
FROM cepa AS c
WHERE NOT EXISTS (
        SELECT 1
        FROM composicion AS co
        WHERE co.id_cepa = c.id_cepa
      )
  AND NOT EXISTS (
        SELECT 1
        FROM parcela AS p
        WHERE p.id_cepa = c.id_cepa
      );

ROLLBACK;


-- =============================================================================
-- D3 · La sala de una localidad determinada fue dada de baja: eliminar los
--      empleados de esa sala que trabajaron menos de dos años.
--
-- Estrategia:
--   - Se filtra por nombre de localidad (`localidad.nombre`), que es el
--     parámetro de ejemplo. Si hubiera más de una sala en esa localidad, se
--     aplica a todas sus salas; si la consigna se interpreta con una sala
--     puntual, reemplazar por `s.id_sala = <id>`.
--   - "Trabajaron menos de dos años" se mide con `fn_antiguedad_anios`
--     (consigna 5.3: filtrar por antigüedad con la función, no con aritmética
--     de fechas).
--   - `empleado.id_sala` es FK RESTRICT a sala; borrar empleados no toca salas.
-- =============================================================================
BEGIN;

-- Control previo: empleados que cumplen la condición.
SELECT COUNT(*) AS d3_empleados_a_borrar
FROM empleado AS e
JOIN sala AS s ON s.id_sala = e.id_sala
JOIN localidad AS l ON l.id_localidad = s.id_localidad
WHERE l.nombre = 'General Alvear'
  AND fn_antiguedad_anios(e.fecha_ingreso) < 2;

DELETE FROM empleado AS e
USING sala AS s
JOIN localidad AS l ON l.id_localidad = s.id_localidad
WHERE e.id_sala = s.id_sala
  AND l.nombre = 'General Alvear'
  AND fn_antiguedad_anios(e.fecha_ingreso) < 2;

-- Control posterior: debe devolver 0.
SELECT COUNT(*) AS d3_empleados_restantes
FROM empleado AS e
JOIN sala AS s ON s.id_sala = e.id_sala
JOIN localidad AS l ON l.id_localidad = s.id_localidad
WHERE l.nombre = 'General Alvear'
  AND fn_antiguedad_anios(e.fecha_ingreso) < 2;

ROLLBACK;


-- =============================================================================
-- D4 · Borrar los clientes socios que nunca compraron y se dieron de alta
--      hace más de 5 años.
--
-- Estrategia:
--   - EXISTS sobre `socio` para asegurar el subtipo.
--   - NOT EXISTS sobre `comprobante` para "nunca compraron".
--   - Se borra desde `cliente`; la fila de `socio` se elimina por CASCADE
--     (PK = FK). Si el cliente tuviera comprobantes, la FK RESTRICT de
--     `comprobante.id_cliente` lo impediría, pero el NOT EXISTS ya lo excluye.
-- =============================================================================
BEGIN;

-- Control previo: socios sin compras y con alta mayor a 5 años.
SELECT COUNT(*) AS d4_clientes_a_borrar
FROM cliente AS cl
WHERE cl.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND EXISTS (
        SELECT 1
        FROM socio AS s
        WHERE s.id_cliente = cl.id_cliente
      )
  AND NOT EXISTS (
        SELECT 1
        FROM comprobante AS c
        WHERE c.id_cliente = cl.id_cliente
      );

DELETE FROM cliente AS cl
WHERE cl.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND EXISTS (
        SELECT 1
        FROM socio AS s
        WHERE s.id_cliente = cl.id_cliente
      )
  AND NOT EXISTS (
        SELECT 1
        FROM comprobante AS c
        WHERE c.id_cliente = cl.id_cliente
      );

-- Control posterior: debe devolver 0.
SELECT COUNT(*) AS d4_clientes_restantes
FROM cliente AS cl
WHERE cl.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND EXISTS (
        SELECT 1
        FROM socio AS s
        WHERE s.id_cliente = cl.id_cliente
      )
  AND NOT EXISTS (
        SELECT 1
        FROM comprobante AS c
        WHERE c.id_cliente = cl.id_cliente
      );

ROLLBACK;


-- =============================================================================
-- D5 · Eliminar los ingresos en estado procesado de hace más de 365 días.
--
-- Estrategia:
--   - Se filtra por `estado = 'procesado'` y por `fecha`.
--   - `renglon_ingreso` se borra por CASCADE desde `ingreso`.
--
-- NOTA DE INTEGRACIÓN CON P1 (RN-12):
--   El trigger que bloquea cambios en renglones de ingreso/transferencia
--   cuando el documento no está en confección puede rechazar también el
--   borrado en cascada de un ingreso procesado. Si eso ocurre, NO se debe
--   desactivar el trigger a ciegas: coordinar con P1 una excepción explícita
--   para el borrado histórico (por ejemplo, un procedimiento que valide el
--   estado y haga el mantenimiento dentro de una transacción). Este archivo
--   deja la consulta canónica; la prueba real debe registrar el SQLSTATE
--   observado y la decisión del equipo.
-- =============================================================================
BEGIN;

-- Control previo: ingresos procesados de más de 365 días.
SELECT COUNT(*) AS d5_ingresos_a_borrar
FROM ingreso AS i
WHERE i.estado = 'procesado'
  AND i.fecha < CURRENT_DATE - INTERVAL '365 days';

DELETE FROM ingreso AS i
WHERE i.estado = 'procesado'
  AND i.fecha < CURRENT_DATE - INTERVAL '365 days';

-- Control posterior: debe devolver 0.
SELECT COUNT(*) AS d5_ingresos_restantes
FROM ingreso AS i
WHERE i.estado = 'procesado'
  AND i.fecha < CURRENT_DATE - INTERVAL '365 days';

ROLLBACK;


-- =============================================================================
-- D6 · Borrar los clientes socios sin compras que viven en una localidad
--      específica.
--
-- Estrategia:
--   - EXISTS sobre `socio` para el subtipo.
--   - NOT EXISTS sobre `comprobante` para "sin compras".
--   - Join con `localidad` por nombre (parámetro de ejemplo). También se podría
--     usar `id_localidad` si el dataset lo prefiere.
--   - Al borrar `cliente`, la fila de `socio` se elimina por CASCADE.
-- =============================================================================
BEGIN;

-- Control previo: socios sin compras de la localidad indicada.
SELECT COUNT(*) AS d6_clientes_a_borrar
FROM cliente AS cl
JOIN localidad AS l ON l.id_localidad = cl.id_localidad
WHERE l.nombre = 'San Rafael'
  AND EXISTS (
        SELECT 1
        FROM socio AS s
        WHERE s.id_cliente = cl.id_cliente
      )
  AND NOT EXISTS (
        SELECT 1
        FROM comprobante AS c
        WHERE c.id_cliente = cl.id_cliente
      );

DELETE FROM cliente AS cl
USING localidad AS l
WHERE l.id_localidad = cl.id_localidad
  AND l.nombre = 'San Rafael'
  AND EXISTS (
        SELECT 1
        FROM socio AS s
        WHERE s.id_cliente = cl.id_cliente
      )
  AND NOT EXISTS (
        SELECT 1
        FROM comprobante AS c
        WHERE c.id_cliente = cl.id_cliente
      );

-- Control posterior: debe devolver 0.
SELECT COUNT(*) AS d6_clientes_restantes
FROM cliente AS cl
JOIN localidad AS l ON l.id_localidad = cl.id_localidad
WHERE l.nombre = 'San Rafael'
  AND EXISTS (
        SELECT 1
        FROM socio AS s
        WHERE s.id_cliente = cl.id_cliente
      )
  AND NOT EXISTS (
        SELECT 1
        FROM comprobante AS c
        WHERE c.id_cliente = cl.id_cliente
      );

ROLLBACK;
