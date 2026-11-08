-- =============================================================================
-- 005_triggers.sql · TPI «Bodegas del Atuel» · UTN FRSR — Bases de Datos 2026
-- Etapa 2 · Triggers de reglas de negocio (tarea 2.4).
--
-- Depende de: 001_esquema.sql, 002_constraints.sql, 003_funciones.sql y
--             004_procedimientos.sql. Orden: 001 → 002 → 003 → 004 → 005.
--
-- Alcance: que las reglas RN-05, RN-08, RN-09, RN-10, RN-11, RN-12 y RN-13 se
-- cumplan dentro de la base, sin importar quien la use. Cada error de negocio
-- usa RAISE EXCEPTION '[RN-XX] Mensaje' (SQLSTATE P0001) y la API lo traduce a
-- HTTP 409 (docs/contratos.md §3).
--
-- DECISIONES (ver plan_005.md §5, §6 y §12)
--
--  1. UN SOLO trigger BEFORE INSERT sobre renglon_comprobante completa la linea
--     (precio_unitario, descuento, subtotal) y valida el stock con
--     SELECT ... FOR UPDATE. UN SOLO trigger AFTER INSERT descuenta el stock y
--     recalcula la cabecera. El documento es inmutable y T9 (BEFORE UPDATE OR
--     DELETE) rechaza cualquier cambio de sus renglones, porque no hay logica de
--     recalculo de totales ni de stock. El borrado en cascada desde la cabecera
--     se permite para no romper la consigna D1 (docs/SPEC.md §1.2).
--     PostgreSQL dispara los triggers del mismo evento en orden alfabetico; para
--     no depender de ese orden, cada evento y tabla criticos tienen UNA sola
--     funcion que hace todo.
--
--  2. INSERT sobre ingreso y transferencia solo acepta estado 'en_confeccion'
--     (D2). Cierra el atajo de crear documentos ya terminados.
--
--  3. auditoria_precio solo registra cambios reales de precio_venta: la clausula
--     WHEN del trigger evita auditar cambios de otros atributos (D3).
--
--  4. T8 (RN-05) no exige 100 % cuando el vino fue borrado en cascada; T6
--     (RN-12) no valida cuando la cabecera ya no existe. Ambos borrados en
--     cascada (vino → composicion, ingreso/transferencia → renglones) no deben
--     hacer fallar el COMMIT ni el DELETE.
--
--  5. La validacion de estado de este archivo convive con la de
--     004_procedimientos.sql (plan_004.md §3 y §14): los mensajes de hechos
--     identicos se alinean para no divergir.
--
--  6. HALLAZGO R-001 · la integridad no depende del privilegio del llamador.
--     T1, T2 y T7 se declaran LANGUAGE plpgsql SECURITY DEFINER con
--     SET search_path = pg_catalog, public en el mismo CREATE OR REPLACE (un
--     replace sin atributos los resetea a INVOKER). Con DEFINER, 007 puede
--     quitarle a app_rw el DML de tabla completa sobre las tablas criticas:
--     una inyeccion SQL en la API ya no puede saltarse los triggers para
--     modificar totales, stocks ni auditoria a mano.
--       · T1 hace SELECT ... FOR UPDATE sobre stock_sala y el lock exige
--         privilegio UPDATE; sin DEFINER devuelve 42501 (verificado
--         empiricamente).
--       · T2 escribe stock_sala y la cabecera del comprobante.
--       · T7 inserta en auditoria_precio, que app_rw solo puede leer.
--     Las demas funciones (T3, T4, T5, T6, T8 y T9) quedan INVOKER a
--     proposito: solo leen tablas sobre las que app_rw conserva SELECT y no
--     necesitan privilegios elevados; dejarlas INVOKER reduce la superficie de
--     funciones DEFINER. El search_path fijo evita search_path hijacking.
--
--  7. R-003/R-005/R-006 · al salir de en_confeccion se congelan los datos de
--     cabecera del ingreso y la sala de la transferencia; las claves de los
--     renglones de ingreso/transferencia son inmutables.
--
-- Mensajes sin tildes ni caracteres especiales (convencion de contratos.md).
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. VENTA · renglon_comprobante (RN-08, RN-09, inmutabilidad con RN pendiente)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T1 · fn_tg_renglon_venta_completar · BEFORE INSERT ON renglon_comprobante
-- Completa la linea con el precio vigente del vino y el descuento del cliente
-- (RN-08) y valida el stock de la sala con un lock de fila (RN-09). El lock se
-- mantiene hasta el COMMIT y serializa dos ventas concurrentes de la ultima
-- botella (anexo A.5).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_renglon_venta_completar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_sala       integer;
    v_precio     numeric(12,2);
    v_disponible integer;
    v_porc       numeric(5,2);
    v_bruto      numeric(12,2);
BEGIN
    -- Cabecera y descuento del cliente: definen la sala y el porcentaje. El
    -- porcentaje viene de cliente.descuento, columna generada desde tipo (R-002),
    -- para que exista una sola fuente de verdad.
    SELECT cb.id_sala, cl.descuento
      INTO v_sala, v_porc
      FROM comprobante AS cb
      JOIN cliente AS cl ON cl.id_cliente = cb.id_cliente
     WHERE cb.nro_comprobante = NEW.nro_comprobante;

    -- Precio vigente del vino.
    SELECT precio_venta
      INTO v_precio
      FROM vino
     WHERE cod_vino = NEW.cod_vino;

    -- Bloqueo y lectura del stock (RN-09). Si no hay fila, el stock es 0.
    SELECT cantidad
      INTO v_disponible
      FROM stock_sala
     WHERE id_sala = v_sala
       AND cod_vino = NEW.cod_vino
       FOR UPDATE;

    IF COALESCE(v_disponible, 0) < NEW.cantidad THEN
        RAISE EXCEPTION '[RN-09] Stock insuficiente del vino % en la sala %: disponible %, solicitado %',
            NEW.cod_vino, v_sala, COALESCE(v_disponible, 0), NEW.cantidad;
    END IF;

    -- Calculo RN-08 (docs/contratos.md §5): redondeo explicito a 2 decimales.
    NEW.precio_unitario := v_precio;
    v_bruto := NEW.cantidad * v_precio;
    NEW.descuento := ROUND(v_bruto * (v_porc / 100.0), 2);
    NEW.subtotal := v_bruto - NEW.descuento;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_tg_renglon_venta_completar() IS
    'RN-08 y RN-09. BEFORE INSERT de renglon_comprobante: completa precio_unitario, descuento y subtotal, y valida el stock de la sala con FOR UPDATE. SECURITY DEFINER con search_path fijo (pg_catalog, public): el FOR UPDATE exige privilegio UPDATE sobre stock_sala, que app_rw ya no tiene.';

-- RN-08, RN-09 · completa y valida la linea de venta antes de insertarla.
DROP TRIGGER IF EXISTS tg_renglon_comprobante_bi ON renglon_comprobante;
CREATE TRIGGER tg_renglon_comprobante_bi
    BEFORE INSERT ON renglon_comprobante
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_renglon_venta_completar();

-- -----------------------------------------------------------------------------
-- T2 · fn_tg_renglon_venta_actualizar · AFTER INSERT ON renglon_comprobante
-- Descuenta la cantidad vendida del stock de la sala y recalcula subtotal,
-- descuento y total de la cabecera en UN solo UPDATE (ck_comprobante_total exige
-- total = subtotal - descuento). Reutiliza fn_total_comprobante de 003.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_renglon_venta_actualizar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_sala integer;
BEGIN
    SELECT id_sala
      INTO v_sala
      FROM comprobante
     WHERE nro_comprobante = NEW.nro_comprobante;

    -- La fila existe y quedo bloqueada en el BEFORE; el CHECK es red de seguridad.
    UPDATE stock_sala
       SET cantidad = cantidad - NEW.cantidad
     WHERE id_sala = v_sala
       AND cod_vino = NEW.cod_vino;

    -- Las tres columnas de cabecera en un unico UPDATE.
    UPDATE comprobante
       SET (subtotal, descuento, total) = (
               SELECT f.subtotal, f.descuento, f.total
                 FROM fn_total_comprobante(NEW.nro_comprobante) AS f
           )
     WHERE nro_comprobante = NEW.nro_comprobante;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION fn_tg_renglon_venta_actualizar() IS
    'RN-08 y RN-09. AFTER INSERT de renglon_comprobante: descuenta stock_sala y recalcula subtotal, descuento y total de la cabecera en un solo UPDATE. SECURITY DEFINER con search_path fijo (pg_catalog, public): escribe stock_sala y comprobante, sobre los que app_rw ya no tiene DML.';

-- RN-08, RN-09 · descuenta stock y actualiza los totales de la cabecera.
DROP TRIGGER IF EXISTS tg_renglon_comprobante_ai ON renglon_comprobante;
CREATE TRIGGER tg_renglon_comprobante_ai
    AFTER INSERT ON renglon_comprobante
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_renglon_venta_actualizar();

-- -----------------------------------------------------------------------------
-- T9 · fn_tg_renglon_venta_inmutable · BEFORE UPDATE OR DELETE ON renglon_comprobante
-- El comprobante emitido es inmutable: no existe logica de recalculo de totales
-- ni de stock, asi que cualquier UPDATE o DELETE directo de sus renglones se
-- rechaza. Unica excepcion: el borrado en cascada desde la cabecera (consigna
-- D1), cuando el comprobante ya no existe.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_renglon_venta_inmutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Borrado en cascada desde la cabecera (consigna D1): no bloquear.
    IF TG_OP = 'DELETE' AND NOT EXISTS (
        SELECT 1 FROM comprobante
         WHERE nro_comprobante = OLD.nro_comprobante
    ) THEN
        RETURN OLD;
    END IF;

    RAISE EXCEPTION '[RN-XX] Los comprobantes emitidos son inmutables y no admiten modificaciones.';
END;
$$;

COMMENT ON FUNCTION fn_tg_renglon_venta_inmutable() IS
    'Inmutabilidad (RN pendiente de numerar). BEFORE UPDATE OR DELETE de renglon_comprobante: rechaza cambios de un comprobante emitido; permite el borrado en cascada cuando la cabecera ya no existe (consigna D1).';

-- Inmutabilidad · los renglones emitidos no se modifican ni se borran directo.
DROP TRIGGER IF EXISTS tg_renglon_comprobante_bud ON renglon_comprobante;
CREATE TRIGGER tg_renglon_comprobante_bud
    BEFORE UPDATE OR DELETE ON renglon_comprobante
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_renglon_venta_inmutable();

-- =============================================================================
-- 2. INGRESO · estado (RN-10)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T3 · fn_tg_ingreso_estado · BEFORE INSERT OR UPDATE ON ingreso
-- El INSERT solo acepta 'en_confeccion' (D2). El UPDATE solo permite los avances
-- de un paso en_confeccion → terminado y terminado → procesado. Los retrocesos y
-- saltos se rechazan. sp_procesar_ingreso hace terminado → procesado: pasa sin
-- friccion.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_ingreso_estado()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado IS DISTINCT FROM 'en_confeccion' THEN
            RAISE EXCEPTION '[RN-10] El ingreso % debe crecer en estado en_confeccion (recibido: %)',
                NEW.cod_ingreso, NEW.estado;
        END IF;
    ELSE
        IF NEW.estado IS DISTINCT FROM OLD.estado THEN
            IF NOT (
                (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
                OR (OLD.estado = 'terminado' AND NEW.estado = 'procesado')
            ) THEN
                RAISE EXCEPTION '[RN-10] Transicion de estado invalida en el ingreso %: % -> %',
                    NEW.cod_ingreso, OLD.estado, NEW.estado;
            END IF;
        END IF;

        -- R-003: datos de cabecera congelados al salir de en_confeccion.
        IF (OLD.estado IS DISTINCT FROM 'en_confeccion'
            OR NEW.estado IS DISTINCT FROM 'en_confeccion')
           AND (NEW.fecha            IS DISTINCT FROM OLD.fecha
             OR NEW.id_transportista IS DISTINCT FROM OLD.id_transportista
             OR NEW.cuit_bodega      IS DISTINCT FROM OLD.cuit_bodega) THEN
            RAISE EXCEPTION '[RN-10] Los datos de cabecera del ingreso % no pueden modificarse una vez que salio de en_confeccion',
                NEW.cod_ingreso;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_tg_ingreso_estado() IS
    'RN-10/R-003. BEFORE INSERT OR UPDATE de ingreso: alta en_confeccion, avance de estado de un paso y cabecera congelada al salir de en_confeccion.';

-- RN-10 · los estados del ingreso solo avanzan.
DROP TRIGGER IF EXISTS tg_ingreso_estado ON ingreso;
CREATE TRIGGER tg_ingreso_estado
    BEFORE INSERT OR UPDATE ON ingreso
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_ingreso_estado();

-- =============================================================================
-- 3. TRANSFERENCIA · estado y fecha (RN-11)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T4 · fn_tg_transferencia_estado · BEFORE INSERT OR UPDATE ON transferencia
-- Misma logica que T3 con mensajes [RN-11]. sp_procesar_transferencia hace
-- terminado → procesado: transicion valida.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_transferencia_estado()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado IS DISTINCT FROM 'en_confeccion' THEN
            RAISE EXCEPTION '[RN-11] La transferencia % debe crecer en estado en_confeccion (recibido: %)',
                NEW.nro_solicitud, NEW.estado;
        END IF;
    ELSE
        IF NEW.estado IS DISTINCT FROM OLD.estado THEN
            IF NOT (
                (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
                OR (OLD.estado = 'terminado' AND NEW.estado = 'procesado')
            ) THEN
                RAISE EXCEPTION '[RN-11] Transicion de estado invalida en la transferencia %: % -> %',
                    NEW.nro_solicitud, OLD.estado, NEW.estado;
            END IF;
        END IF;

        -- R-005: id_sala congelada al salir de en_confeccion.
        IF (OLD.estado IS DISTINCT FROM 'en_confeccion'
            OR NEW.estado IS DISTINCT FROM 'en_confeccion')
           AND NEW.id_sala IS DISTINCT FROM OLD.id_sala THEN
            RAISE EXCEPTION '[RN-11] Los datos de cabecera de la transferencia % no pueden modificarse una vez que salio de en_confeccion',
                NEW.nro_solicitud;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_tg_transferencia_estado() IS
    'RN-11/R-005. BEFORE INSERT OR UPDATE de transferencia: alta en_confeccion, avance de estado de un paso y id_sala congelada al salir de en_confeccion.';

-- RN-11 · los estados de la transferencia solo avanzan.
DROP TRIGGER IF EXISTS tg_transferencia_estado ON transferencia;
CREATE TRIGGER tg_transferencia_estado
    BEFORE INSERT OR UPDATE ON transferencia
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_transferencia_estado();

-- -----------------------------------------------------------------------------
-- T5 · fn_tg_transferencia_fecha · BEFORE INSERT OR UPDATE ON transferencia
-- El INSERT fuerza fecha_confeccion = CURRENT_DATE (la API no la envia); el
-- UPDATE rechaza cualquier cambio. T4 y T5 son funciones distintas sobre el mismo
-- evento pero miran columnas propias, asi que no compiten.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_transferencia_fecha()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
    ELSIF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
        RAISE EXCEPTION '[RN-11] La fecha de confeccion de la transferencia % no puede modificarse',
            NEW.nro_solicitud;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_tg_transferencia_fecha() IS
    'RN-11. BEFORE INSERT OR UPDATE de transferencia: fuerza fecha_confeccion a CURRENT_DATE al insertar y rechaza modificaciones al actualizar.';

-- RN-11 · fecha_confeccion de la transferencia forzada e inmutable.
DROP TRIGGER IF EXISTS tg_transferencia_fecha ON transferencia;
CREATE TRIGGER tg_transferencia_fecha
    BEFORE INSERT OR UPDATE ON transferencia
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_transferencia_fecha();

-- =============================================================================
-- 4. RENGLONES DE DOCUMENTO · renglon_ingreso y renglon_transferencia (RN-12)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T6 · fn_tg_renglon_documento_bloqueo · BEFORE INSERT OR UPDATE OR DELETE
-- Los renglones solo son editables con el documento en 'en_confeccion'. Una sola
-- funcion y dos CREATE TRIGGER; TG_TABLE_NAME elige la cabecera. DELETE mira OLD,
-- INSERT mira NEW y UPDATE cualquiera de los dos (la clave no cambia). Si la
-- cabecera ya no existe (borrado en cascada desde ingreso/transferencia), no se
-- valida: el CASCADE no debe hacer fallar el DELETE ni el COMMIT.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_renglon_documento_bloqueo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
    v_doc    integer;
BEGIN
    -- R-006: la clave de un renglon nunca cambia. Se borra y se reinserta.
    IF TG_OP = 'UPDATE' THEN
        IF TG_TABLE_NAME = 'renglon_ingreso' THEN
            IF NEW.cod_ingreso IS DISTINCT FROM OLD.cod_ingreso
               OR NEW.cod_vino IS DISTINCT FROM OLD.cod_vino THEN
                RAISE EXCEPTION '[RN-12] La clave de un renglon de % no puede modificarse; borre la fila y vuelva a insertarla',
                    TG_TABLE_NAME;
            END IF;
        ELSE
            IF NEW.nro_solicitud IS DISTINCT FROM OLD.nro_solicitud
               OR NEW.cod_vino IS DISTINCT FROM OLD.cod_vino THEN
                RAISE EXCEPTION '[RN-12] La clave de un renglon de % no puede modificarse; borre la fila y vuelva a insertarla',
                    TG_TABLE_NAME;
            END IF;
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'renglon_ingreso' THEN
        IF TG_OP = 'DELETE' THEN
            v_doc := OLD.cod_ingreso;
        ELSE
            v_doc := NEW.cod_ingreso;
        END IF;

        SELECT estado INTO v_estado
          FROM ingreso
         WHERE cod_ingreso = v_doc;
    ELSE
        IF TG_OP = 'DELETE' THEN
            v_doc := OLD.nro_solicitud;
        ELSE
            v_doc := NEW.nro_solicitud;
        END IF;

        SELECT estado INTO v_estado
          FROM transferencia
         WHERE nro_solicitud = v_doc;
    END IF;

    -- Cabecera borrada en cascada: no hay nada que validar.
    IF NOT FOUND THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        RETURN NEW;
    END IF;

    IF v_estado <> 'en_confeccion' THEN
        RAISE EXCEPTION '[RN-12] No se pueden modificar renglones de un documento en estado %',
            v_estado;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_tg_renglon_documento_bloqueo() IS
    'RN-12/R-006. BEFORE INSERT/UPDATE/DELETE de renglon_ingreso y renglon_transferencia: solo permite editar renglones en_confeccion, rechaza cambios de clave y omite validacion tras borrado en cascada.';

-- RN-12 · renglones de ingreso editables solo en en_confeccion.
DROP TRIGGER IF EXISTS tg_renglon_ingreso_biud ON renglon_ingreso;
CREATE TRIGGER tg_renglon_ingreso_biud
    BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_renglon_documento_bloqueo();

-- RN-12 · renglones de transferencia editables solo en en_confeccion.
DROP TRIGGER IF EXISTS tg_renglon_transferencia_biud ON renglon_transferencia;
CREATE TRIGGER tg_renglon_transferencia_biud
    BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_renglon_documento_bloqueo();

-- =============================================================================
-- 5. VINO · auditoria de precio (RN-13)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T7 · fn_tg_vino_precio_auditoria · AFTER UPDATE ON vino
-- Registra en auditoria_precio solo los cambios reales de precio_venta (el WHEN
-- del trigger descarta los UPDATE que tocan otros atributos). El usuario sale de
-- app.usuario; si la API no lo seteo, se usa session_user (dentro de DEFINER
-- current_user es el owner).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_vino_precio_auditoria()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
    VALUES (
        NEW.cod_vino,
        OLD.precio_venta,
        NEW.precio_venta,
        CURRENT_TIMESTAMP,
        COALESCE(NULLIF(current_setting('app.usuario', true), ''), session_user)
    );

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION fn_tg_vino_precio_auditoria() IS
    'RN-13. AFTER UPDATE de vino: registra en auditoria_precio los cambios reales de precio_venta con el usuario de app.usuario o session_user. SECURITY DEFINER con search_path fijo (pg_catalog, public): inserta en auditoria_precio, que app_rw solo puede leer.';

-- RN-13 · auditoria de cambios de precio, solo cuando precio_venta cambia.
DROP TRIGGER IF EXISTS tg_vino_precio_auditoria ON vino;
CREATE TRIGGER tg_vino_precio_auditoria
    AFTER UPDATE ON vino
    FOR EACH ROW
    WHEN (OLD.precio_venta IS DISTINCT FROM NEW.precio_venta)
    EXECUTE FUNCTION fn_tg_vino_precio_auditoria();

-- =============================================================================
-- 6. COMPOSICION · suma de cepas 100 % (RN-05)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T8 · fn_tg_composicion_cien · CONSTRAINT TRIGGER AFTER INSERT OR UPDATE OR
--      DELETE ON composicion, DEFERRABLE INITIALLY DEFERRED
-- Difiere la verificacion al COMMIT para permitir insertar varias cepas
-- (40 + 60). Valida el vino afectado (o ambos si un UPDATE cambia cod_vino). Si el
-- vino ya no existe (borrado en cascada desde vino), no valida: el CASCADE no
-- debe hacer fallar el COMMIT.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_composicion_cien()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_vinos integer[];
    v_vino  integer;
    v_suma  numeric(5,2);
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_vinos := ARRAY[NEW.cod_vino];
    ELSIF TG_OP = 'DELETE' THEN
        v_vinos := ARRAY[OLD.cod_vino];
    ELSIF NEW.cod_vino = OLD.cod_vino THEN
        v_vinos := ARRAY[NEW.cod_vino];
    ELSE
        v_vinos := ARRAY[OLD.cod_vino, NEW.cod_vino];
    END IF;

    FOREACH v_vino IN ARRAY v_vinos
    LOOP
        -- Vino borrado en cascada: no hay composicion que sumar.
        IF NOT EXISTS (SELECT 1 FROM vino WHERE cod_vino = v_vino) THEN
            CONTINUE;
        END IF;

        SELECT COALESCE(SUM(porcentaje), 0)
          INTO v_suma
          FROM composicion
         WHERE cod_vino = v_vino;

        IF v_suma <> 100 THEN
            RAISE EXCEPTION '[RN-05] La composicion del vino % suma %, debe sumar 100',
                v_vino, v_suma;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION fn_tg_composicion_cien() IS
    'RN-05. Constraint trigger diferido de composicion: verifica al COMMIT que la composicion del vino afectado sume 100; omite vinos borrados en cascada.';

-- RN-05 · la composicion de cepas suma 100 % (verificacion diferida al COMMIT).
DROP TRIGGER IF EXISTS tg_composicion_cien ON composicion;
CREATE CONSTRAINT TRIGGER tg_composicion_cien
    AFTER INSERT OR UPDATE OR DELETE ON composicion
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION fn_tg_composicion_cien();

COMMIT;
