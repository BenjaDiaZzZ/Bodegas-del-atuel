-- =============================================================================
-- 004_procedimientos.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Etapa 2 · Procedimientos transaccionales: sp_procesar_ingreso y
--           sp_procesar_transferencia (RN-10, RN-11).
--
-- Depende de: 001_esquema.sql y 002_constraints.sql. No usa 003 ni 005, así que
--             el orden 001 → 002 → 003 → 004 → 005 se respeta sin problemas.
--
-- DECISIONES (ver docs/decisiones_de_diseno.md)
--
--  1. NO hay COMMIT ni ROLLBACK dentro de los procedimientos. El llamador es
--     dueño de la transacción (la API abre BEGIN; una llamada suelta fuera de
--     BEGIN es una transacción por sí sola). Si algo falla, la excepción sube y
--     se revierte TODO: estado y stocks. Un COMMIT interno, además, falla con
--     SQLSTATE 2D000 cuando el CALL está dentro de un BEGIN explícito.
--
--  2. Validar TODO antes de escribir. La transferencia recorre primero todos los
--     vinos (bloqueando y comprobando el stock del depósito) y recién después
--     modifica nada. Así el error de «sin stock» es claro (P0001, 409) y no el
--     genérico 23514 del CHECK.
--
--  3. ORDEN DE BLOQUEO (único, vale para todo el sistema):
--        documento  →  renglones del documento (cod_vino ASC)
--                   →  stock_deposito (cod_vino ASC)  →  stock_sala (cod_vino ASC)
--     Dos transacciones que procesan documentos distintos con vinos en común
--     toman los locks en el mismo orden y no pueden trabarse entre sí.
--     La venta (trigger de 005) solo bloquea stock_sala: para no cruzarse con
--     este orden, la API debe enviar los renglones del comprobante ordenados
--     por cod_vino.
--     Los renglones se bloquean antes de validarlos. El lock de la cabecera no
--     alcanza: un UPDATE/DELETE del detalle no toca la cabecera, así que sin el
--     lock del renglón otra sesión podría editarlo entre la validación y la
--     escritura (TOCTOU) y el procedimiento descontaría un conjunto distinto
--     del que validó. Con el renglón bloqueado, el conjunto leído es estable y
--     es exactamente el que se descuenta y se acredita.
--
--  4. Filas de stock ausentes:
--       · Ingreso: el depósito puede no tener fila del vino todavía; se crea con
--         un upsert atómico (INSERT … ON CONFLICT DO UPDATE). Un SELECT FOR UPDATE
--         seguido de INSERT tiene una carrera: dos ingresos simultáneos del mismo
--         vino nuevo hacen fallar al segundo con 23505.
--       · Transferencia, depósito: la fila ausente es un ERROR (nunca se asume 0).
--       · Transferencia, sala destino: la fila se crea con upsert.
--
--  5. Documento sin renglones: es un error, para no dejar un documento
--     «procesado» que no movió nada.
--
--  6. Los renglones se agrupan por cod_vino (GROUP BY). La PK ya impide
--     repetidos; es una defensa extra, sin costo.
--
--  7. HALLAZGO R-001 · ambos procedimientos son LANGUAGE plpgsql SECURITY
--     DEFINER con SET search_path = pg_catalog, public. Escriben
--     stock_deposito, stock_sala y el estado de los documentos, y 007 ya no le
--     da a app_rw DML directo sobre esas tablas: la API solo puede mover stock
--     y avanzar estados llamando a los procedimientos, con los privilegios del
--     owner. El search_path fijo evita search_path hijacking. El resto de las
--     rutinas del esquema sigue INVOKER.
--
-- CONTRATO DE ERRORES (la API los traduce según docs/contratos.md)
--     P0001  Regla de negocio rechazada. Mensaje '[RN-10] …' o '[RN-11] …'.   → 409
--     P0002  El documento no existe.                                          → 404
--     55P03  Espera de lock vencida. Solo ocurre si el despliegue configura un
--            lock_timeout/statement_timeout; 007 no lo configura por defecto. → 503 reintento
--     40001 / 40P01  Serialización o deadlock residual.                       → 503 reintento
--
-- NIVEL DE AISLAMIENTO: READ COMMITTED (el predeterminado). El segundo llamador
-- sobre el mismo documento espera en el FOR UPDATE de la cabecera y, al
-- liberarse, ve el estado 'procesado' y falla con RN-10 / RN-11: nunca duplica
-- el stock.
--
-- Mensajes sin acentos ni caracteres especiales (convención de contratos.md).
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- sp_procesar_ingreso(p_cod)
-- Un ingreso TERMINADO suma sus botellas al stock del depósito central y pasa a
-- PROCESADO. Parámetro: p_cod = ingreso.cod_ingreso. Reglas: RN-10.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_cod integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_estado estado_documento;
    r        record;
BEGIN
    -- 1. Cabecera con lock: serializa llamadas concurrentes sobre el mismo ingreso.
    SELECT estado INTO v_estado
      FROM ingreso
     WHERE cod_ingreso = p_cod
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el ingreso %', p_cod
            USING ERRCODE = 'P0002';
    END IF;

    -- 2. Solo un ingreso terminado impacta en el depósito (RN-10). Cubre
    --    en_confeccion y también la llamada repetida (ya procesado).
    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION '[RN-10] El ingreso % no esta terminado (estado actual: %)',
            p_cod, v_estado;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM renglon_ingreso WHERE cod_ingreso = p_cod) THEN
        RAISE EXCEPTION '[RN-10] El ingreso % no tiene renglones', p_cod;
    END IF;

    -- 3. Suma al depósito, vino por vino en orden ascendente (orden de locks).
    --    El upsert crea la fila si el vino todavía no tenía stock en el depósito.
    FOR r IN
        SELECT cod_vino, SUM(cantidad)::integer AS cantidad
          FROM renglon_ingreso
         WHERE cod_ingreso = p_cod
         GROUP BY cod_vino
         ORDER BY cod_vino
    LOOP
        INSERT INTO stock_deposito (cod_vino, cantidad)
        VALUES (r.cod_vino, r.cantidad)
        ON CONFLICT (cod_vino)
        DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;
    END LOOP;

    -- 4. Una vez impactado, pasa a procesado (no retrocede).
    UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = p_cod;
END;
$$;

COMMENT ON PROCEDURE sp_procesar_ingreso(integer) IS
    'RN-10. Procesa un ingreso TERMINADO: suma sus botellas al stock del deposito central y lo pasa a PROCESADO. Parametro: p_cod (cod_ingreso). Errores: P0001 [RN-10] si no esta terminado o no tiene renglones; P0002 si no existe. Todo o nada: no hace COMMIT ni ROLLBACK, el llamador es dueño de la transaccion. SECURITY DEFINER con search_path fijo (pg_catalog, public).';

-- -----------------------------------------------------------------------------
-- sp_procesar_transferencia(p_nro)
-- Una transferencia TERMINADA descuenta sus botellas del depósito central, las
-- suma al stock de la sala solicitante y pasa a PROCESADA.
-- Parámetro: p_nro = transferencia.nro_solicitud. Reglas: RN-11.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_estado estado_documento;
    v_sala   integer;
    v_stock  integer;
    r        record;
    v_vinos  integer[] := '{}';
    v_cants  integer[] := '{}';
    i        integer;
BEGIN
    -- 1. Cabecera con lock.
    SELECT estado, id_sala INTO v_estado, v_sala
      FROM transferencia
     WHERE nro_solicitud = p_nro
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la transferencia %', p_nro
            USING ERRCODE = 'P0002';
    END IF;

    -- 2. Solo una transferencia terminada impacta en el stock (RN-11).
    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION '[RN-11] La transferencia % no esta terminada (estado actual: %)',
            p_nro, v_estado;
    END IF;

    -- 2b. Bloquear los renglones antes de leerlos. El lock de la cabecera no
    --     alcanza: un UPDATE/DELETE del detalle no toca la cabecera, así que sin
    --     este lock otra sesión podría editar el renglón entre la validación y
    --     la escritura (TOCTOU) y se descontaría un conjunto distinto del
    --     validado. El orden sigue la PK (nro_solicitud, cod_vino), igual que un
    --     UPDATE del detalle, así que no introduce ciclos.
    PERFORM 1
       FROM renglon_transferencia
      WHERE nro_solicitud = p_nro
      ORDER BY cod_vino
        FOR UPDATE;

    -- 2c. Documento sin renglones: es un error. Se comprueba DESPUÉS del lock
    --     para que un DELETE concurrente no deje un documento «procesado» sin
    --     haber movido stock.
    IF NOT EXISTS (SELECT 1 FROM renglon_transferencia WHERE nro_solicitud = p_nro) THEN
        RAISE EXCEPTION '[RN-11] La transferencia % no tiene renglones', p_nro;
    END IF;

    -- 3. FASE DE VALIDACION (no escribe nada). Bloquea el stock del depósito de
    --    cada vino, en orden ascendente, comprueba que exista y alcance, y guarda
    --    el conjunto validado para reusarlo tal cual en la escritura.
    FOR r IN
        SELECT cod_vino, SUM(cantidad)::integer AS cantidad
          FROM renglon_transferencia
         WHERE nro_solicitud = p_nro
         GROUP BY cod_vino
         ORDER BY cod_vino
    LOOP
        SELECT cantidad INTO v_stock
          FROM stock_deposito
         WHERE cod_vino = r.cod_vino
           FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION '[RN-11] El deposito no tiene stock registrado del vino %',
                r.cod_vino;
        END IF;

        IF v_stock < r.cantidad THEN
            RAISE EXCEPTION '[RN-11] Stock insuficiente en el deposito del vino %: hay %, se piden %',
                r.cod_vino, v_stock, r.cantidad;
        END IF;

        v_vinos := v_vinos || r.cod_vino;
        v_cants := v_cants || r.cantidad;
    END LOOP;

    -- 4. FASE DE ESCRITURA (recién con todo validado). Consume EXACTAMENTE el
    --    conjunto validado en la fase 3, en el mismo orden ascendente: el
    --    depósito ya está bloqueado; el upsert bloquea la fila de la sala.
    FOR i IN 1 .. array_length(v_vinos, 1)
    LOOP
        UPDATE stock_deposito
           SET cantidad = cantidad - v_cants[i]
         WHERE cod_vino = v_vinos[i];

        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (v_sala, v_vinos[i], v_cants[i])
        ON CONFLICT (id_sala, cod_vino)
        DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;
    END LOOP;

    -- 5. Una vez impactada, pasa a procesada (no retrocede).
    UPDATE transferencia SET estado = 'procesado' WHERE nro_solicitud = p_nro;
END;
$$;

COMMENT ON PROCEDURE sp_procesar_transferencia(integer) IS
    'RN-11. Procesa una transferencia TERMINADA: bloquea los renglones, valida y bloquea el stock del deposito, descuenta EXACTAMENTE el conjunto validado, lo suma a la sala solicitante y la pasa a PROCESADA. Parametro: p_nro (nro_solicitud). Errores: P0001 [RN-11] si no esta terminada, no tiene renglones, falta la fila del deposito o el stock no alcanza; P0002 si no existe. Todo o nada: no hace COMMIT ni ROLLBACK, el llamador es dueño de la transaccion. Orden de locks: documento, renglones ASC, deposito ASC, sala ASC. SECURITY DEFINER con search_path fijo (pg_catalog, public).';

COMMIT;
