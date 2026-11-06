BEGIN;

ALTER DOMAIN cuit_dom ADD CONSTRAINT ck_cuit_dom_formato
    CHECK (VALUE ~ '^[0-9]{11}$');


ALTER TABLE localidad
    ALTER COLUMN codigo_postal SET NOT NULL,
    ALTER COLUMN nombre        SET NOT NULL,
    ALTER COLUMN provincia     SET NOT NULL;
    -- encargado_regional: NULL

-- Código postal argentino de 4 dígitos (Anexo B). Si se adopta CPA,
-- ampliar el patrón a '^([0-9]{4}|[A-Z][0-9]{4}[A-Z]{3})$'.
ALTER TABLE localidad ADD CONSTRAINT ck_localidad_codigo_postal
    CHECK (codigo_postal ~ '^[0-9]{4}$');

ALTER TABLE cepa
    ALTER COLUMN nombre SET NOT NULL,
    ALTER COLUMN tipo   SET NOT NULL;

ALTER TABLE bodega
    ALTER COLUMN razon_social SET NOT NULL,
    ALTER COLUMN domicilio    SET NOT NULL;

ALTER TABLE transportista
    ALTER COLUMN razon_social SET NOT NULL,
    ALTER COLUMN cuit         SET NOT NULL,
    ALTER COLUMN email        SET NOT NULL,
    ALTER COLUMN telefono     SET NOT NULL,
    ALTER COLUMN domicilio    SET NOT NULL;

ALTER TABLE maridaje
    ALTER COLUMN nombre               SET NOT NULL,
    ALTER COLUMN temperatura_servicio SET NOT NULL;

ALTER TABLE finca
    ALTER COLUMN nombre               SET NOT NULL,
    ALTER COLUMN superficie_hectareas SET NOT NULL,
    ALTER COLUMN departamento         SET NOT NULL,
    ALTER COLUMN provincia            SET NOT NULL;

ALTER TABLE sala
    ALTER COLUMN direccion          SET NOT NULL,
    ALTER COLUMN dia_cierre_semanal SET NOT NULL,
    ALTER COLUMN id_localidad       SET NOT NULL;

ALTER TABLE empleado
    ALTER COLUMN nombre        SET NOT NULL,
    ALTER COLUMN fecha_ingreso SET NOT NULL,
    ALTER COLUMN salario       SET NOT NULL,
    ALTER COLUMN id_sala       SET NOT NULL;

ALTER TABLE parcela
    ALTER COLUMN superficie_hectareas SET NOT NULL,
    ALTER COLUMN anio_plantacion      SET NOT NULL,
    ALTER COLUMN id_cepa              SET NOT NULL;

ALTER TABLE vino
    ALTER COLUMN nombre_comercial SET NOT NULL,
    ALTER COLUMN tipo             SET NOT NULL,
    ALTER COLUMN anada            SET NOT NULL,
    ALTER COLUMN presentacion_ml  SET NOT NULL,
    ALTER COLUMN graduacion       SET NOT NULL,
    ALTER COLUMN precio_venta     SET NOT NULL,
    ALTER COLUMN cuit_bodega      SET NOT NULL;

ALTER TABLE cliente
    ALTER COLUMN nombre         SET NOT NULL,
    ALTER COLUMN tipo           SET NOT NULL,
    ALTER COLUMN tipo_documento SET NOT NULL,
    ALTER COLUMN nro_documento  SET NOT NULL,
    ALTER COLUMN direccion      SET NOT NULL,
    ALTER COLUMN id_localidad   SET NOT NULL,
    ALTER COLUMN fecha_alta     SET NOT NULL,
    ALTER COLUMN descuento      SET NOT NULL;

ALTER TABLE lote_uva
    ALTER COLUMN id_finca         SET NOT NULL,
    ALTER COLUMN nro_parcela      SET NOT NULL,
    ALTER COLUMN campania         SET NOT NULL,
    ALTER COLUMN fecha_cosecha    SET NOT NULL,
    ALTER COLUMN kilos_cosechados SET NOT NULL,
    ALTER COLUMN cuit_bodega      SET NOT NULL;

ALTER TABLE composicion
    ALTER COLUMN porcentaje SET NOT NULL;

ALTER TABLE distribuidor
    ALTER COLUMN zona_cobertura   SET NOT NULL,
    ALTER COLUMN nro_habilitacion SET NOT NULL;

ALTER TABLE exportador
    ALTER COLUMN pais_destino_principal SET NOT NULL;

ALTER TABLE permiso_exportacion
    ALTER COLUMN fecha_emision     SET NOT NULL,
    ALTER COLUMN fecha_vencimiento SET NOT NULL;

ALTER TABLE analisis_calidad
    ALTER COLUMN nro_lote     SET NOT NULL,
    ALTER COLUMN fecha        SET NOT NULL,
    ALTER COLUMN grado_brix   SET NOT NULL,
    ALTER COLUMN ph           SET NOT NULL,
    ALTER COLUMN acidez_total SET NOT NULL;

ALTER TABLE auditoria_precio
    ALTER COLUMN cod_vino        SET NOT NULL,
    ALTER COLUMN precio_anterior SET NOT NULL,
    ALTER COLUMN precio_nuevo    SET NOT NULL,
    ALTER COLUMN fecha_hora      SET NOT NULL,
    ALTER COLUMN usuario         SET NOT NULL;

ALTER TABLE comprobante
    ALTER COLUMN fecha      SET NOT NULL,
    ALTER COLUMN id_cliente SET NOT NULL,
    ALTER COLUMN id_sala    SET NOT NULL,
    ALTER COLUMN subtotal   SET NOT NULL,
    ALTER COLUMN descuento  SET NOT NULL,
    ALTER COLUMN total      SET NOT NULL;

ALTER TABLE renglon_comprobante
    ALTER COLUMN cantidad        SET NOT NULL,
    ALTER COLUMN precio_unitario SET NOT NULL,
    ALTER COLUMN descuento       SET NOT NULL,
    ALTER COLUMN subtotal        SET NOT NULL;

ALTER TABLE ingreso
    ALTER COLUMN fecha            SET NOT NULL,
    ALTER COLUMN estado           SET NOT NULL,
    ALTER COLUMN id_transportista SET NOT NULL,
    ALTER COLUMN cuit_bodega      SET NOT NULL;

ALTER TABLE renglon_ingreso
    ALTER COLUMN cantidad SET NOT NULL;

ALTER TABLE transferencia
    ALTER COLUMN id_sala          SET NOT NULL,
    ALTER COLUMN fecha_confeccion SET NOT NULL,
    ALTER COLUMN estado           SET NOT NULL;

ALTER TABLE renglon_transferencia
    ALTER COLUMN cantidad SET NOT NULL;

ALTER TABLE stock_deposito
    ALTER COLUMN cantidad SET NOT NULL;

ALTER TABLE stock_sala
    ALTER COLUMN cantidad SET NOT NULL;

ALTER TABLE vino ADD CONSTRAINT uq_vino_nombre_anada_presentacion
    UNIQUE (nombre_comercial, anada, presentacion_ml);

ALTER TABLE lote_uva ADD CONSTRAINT uq_lote_parcela_campania
    UNIQUE (id_finca, nro_parcela, campania);

ALTER TABLE cliente ADD CONSTRAINT uq_cliente_tipo_nro_documento
    UNIQUE (tipo_documento, nro_documento);

ALTER TABLE localidad ADD CONSTRAINT uq_localidad_cp_nombre_provincia
    UNIQUE (codigo_postal, nombre, provincia);

ALTER TABLE transportista ADD CONSTRAINT uq_transportista_cuit
    UNIQUE (cuit);

ALTER TABLE cepa ADD CONSTRAINT uq_cepa_nombre
    UNIQUE (nombre);

ALTER TABLE maridaje ADD CONSTRAINT uq_maridaje_nombre
    UNIQUE (nombre);

ALTER TABLE distribuidor ADD CONSTRAINT uq_distribuidor_nro_habilitacion
    UNIQUE (nro_habilitacion);

ALTER TABLE sala ADD CONSTRAINT uq_sala_direccion_localidad
    UNIQUE (direccion, id_localidad);

ALTER TABLE cepa ADD CONSTRAINT ck_cepa_tipo
    CHECK (tipo IN ('tinta', 'blanca'));

ALTER TABLE vino ADD CONSTRAINT ck_vino_tipo
    CHECK (tipo IN ('tinto', 'blanco', 'rosado', 'espumante'));

ALTER TABLE cliente ADD CONSTRAINT ck_cliente_tipo
    CHECK (tipo IN ('socio', 'distribuidor', 'exportador'));

ALTER TABLE cliente ADD CONSTRAINT ck_cliente_tipo_documento
    CHECK (tipo_documento IN ('DNI', 'CUIT', 'CUIL', 'PASAPORTE', 'LE', 'LC'));

ALTER TABLE sala ADD CONSTRAINT ck_sala_dia_cierre
    CHECK (dia_cierre_semanal BETWEEN 1 AND 7);

ALTER TABLE vino ADD CONSTRAINT ck_vino_precio_venta
    CHECK (precio_venta > 0);
ALTER TABLE vino ADD CONSTRAINT ck_vino_graduacion
    CHECK (graduacion BETWEEN 5 AND 20);
ALTER TABLE vino ADD CONSTRAINT ck_vino_presentacion
    CHECK (presentacion_ml IN (187, 375, 750, 1500, 3000));
ALTER TABLE vino ADD CONSTRAINT ck_vino_anada
    CHECK (anada BETWEEN 1990 AND 2100);

ALTER TABLE cliente ADD CONSTRAINT ck_cliente_descuento
    CHECK (descuento BETWEEN 0 AND 100);

ALTER TABLE permiso_exportacion ADD CONSTRAINT ck_permiso_fechas
    CHECK (fecha_vencimiento > fecha_emision);

ALTER TABLE empleado ADD CONSTRAINT ck_empleado_salario
    CHECK (salario > 0);
ALTER TABLE finca ADD CONSTRAINT ck_finca_superficie
    CHECK (superficie_hectareas > 0);
ALTER TABLE parcela ADD CONSTRAINT ck_parcela_superficie
    CHECK (superficie_hectareas > 0);
ALTER TABLE parcela ADD CONSTRAINT ck_parcela_nro
    CHECK (nro_parcela > 0);
ALTER TABLE parcela ADD CONSTRAINT ck_parcela_anio_plantacion
    CHECK (anio_plantacion BETWEEN 1900 AND 2100);
ALTER TABLE lote_uva ADD CONSTRAINT ck_lote_kilos
    CHECK (kilos_cosechados > 0);

ALTER TABLE analisis_calidad ADD CONSTRAINT ck_analisis_brix
    CHECK (grado_brix BETWEEN 0 AND 40);
ALTER TABLE analisis_calidad ADD CONSTRAINT ck_analisis_ph
    CHECK (ph BETWEEN 0 AND 14);
ALTER TABLE analisis_calidad ADD CONSTRAINT ck_analisis_acidez
    CHECK (acidez_total > 0);

ALTER TABLE maridaje ADD CONSTRAINT ck_maridaje_temperatura
    CHECK (temperatura_servicio BETWEEN 0 AND 30);
ALTER TABLE composicion ADD CONSTRAINT ck_composicion_porcentaje
    CHECK (porcentaje > 0 AND porcentaje <= 100);

ALTER TABLE auditoria_precio ADD CONSTRAINT ck_auditoria_precios
    CHECK (precio_anterior > 0 AND precio_nuevo > 0);

ALTER TABLE comprobante ADD CONSTRAINT ck_comprobante_importes
    CHECK (subtotal >= 0 AND descuento >= 0 AND total >= 0);
ALTER TABLE comprobante ADD CONSTRAINT ck_comprobante_total
    CHECK (total = subtotal - descuento);

ALTER TABLE renglon_comprobante ADD CONSTRAINT ck_renglon_comprobante_cantidad
    CHECK (cantidad > 0);
ALTER TABLE renglon_comprobante ADD CONSTRAINT ck_renglon_comprobante_precio
    CHECK (precio_unitario > 0);

-- descuento es un importe (NUMERIC(12,2)), no un porcentaje:
-- el porcentaje vive en cliente.descuento.
ALTER TABLE renglon_comprobante ADD CONSTRAINT ck_renglon_comprobante_descuento
    CHECK (descuento >= 0);
ALTER TABLE renglon_comprobante ADD CONSTRAINT ck_renglon_comprobante_subtotal
    CHECK (subtotal >= 0);

ALTER TABLE renglon_ingreso ADD CONSTRAINT ck_renglon_ingreso_cantidad
    CHECK (cantidad > 0);
ALTER TABLE renglon_transferencia ADD CONSTRAINT ck_renglon_transferencia_cantidad
    CHECK (cantidad > 0);

ALTER TABLE stock_sala ADD CONSTRAINT ck_stock_sala_cantidad
    CHECK (cantidad >= 0);
ALTER TABLE stock_deposito ADD CONSTRAINT ck_stock_deposito_cantidad
    CHECK (cantidad >= 0);

ALTER TABLE ingreso       ALTER COLUMN estado SET DEFAULT 'en_confeccion';
ALTER TABLE transferencia ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE cliente       ALTER COLUMN fecha_alta       SET DEFAULT CURRENT_DATE;
ALTER TABLE comprobante   ALTER COLUMN fecha            SET DEFAULT CURRENT_DATE;
ALTER TABLE ingreso       ALTER COLUMN fecha            SET DEFAULT CURRENT_DATE;

ALTER TABLE transferencia ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE;

ALTER TABLE comprobante   ALTER COLUMN subtotal  SET DEFAULT 0;
ALTER TABLE comprobante   ALTER COLUMN descuento SET DEFAULT 0;
ALTER TABLE comprobante   ALTER COLUMN total     SET DEFAULT 0;

ALTER TABLE stock_sala     ALTER COLUMN cantidad SET DEFAULT 0;
ALTER TABLE stock_deposito ALTER COLUMN cantidad SET DEFAULT 0;

ALTER TABLE auditoria_precio ALTER COLUMN fecha_hora SET DEFAULT now();


ALTER TABLE cliente ADD CONSTRAINT uq_cliente_id_tipo
    UNIQUE (id_cliente, tipo);

-- Las FK compuestas usan ON UPDATE RESTRICT: el CHECK del subtipo fija el
-- tipo (socio/distribuidor/exportador), por lo que un CASCADE desde cliente
-- intentaría copiar un tipo distinto y violaría ese CHECK. Para cambiar el
-- tipo de un cliente hay que borrar primero su fila de subtipo.
-- Socio
ALTER TABLE socio DROP CONSTRAINT fk_socio_cliente;
ALTER TABLE socio
    ADD COLUMN tipo varchar(15) NOT NULL DEFAULT 'socio',
    ADD CONSTRAINT ck_socio_tipo CHECK (tipo = 'socio'),
    ADD CONSTRAINT fk_socio_cliente FOREIGN KEY (id_cliente, tipo)
        REFERENCES cliente (id_cliente, tipo)
        ON DELETE CASCADE ON UPDATE RESTRICT;

-- Distribuidor
ALTER TABLE distribuidor DROP CONSTRAINT fk_distribuidor_cliente;
ALTER TABLE distribuidor
    ADD COLUMN tipo varchar(15) NOT NULL DEFAULT 'distribuidor',
    ADD CONSTRAINT ck_distribuidor_tipo CHECK (tipo = 'distribuidor'),
    ADD CONSTRAINT fk_distribuidor_cliente FOREIGN KEY (id_cliente, tipo)
        REFERENCES cliente (id_cliente, tipo)
        ON DELETE CASCADE ON UPDATE RESTRICT;

-- Exportador
ALTER TABLE exportador DROP CONSTRAINT fk_exportador_cliente;
ALTER TABLE exportador
    ADD COLUMN tipo varchar(15) NOT NULL DEFAULT 'exportador',
    ADD CONSTRAINT ck_exportador_tipo CHECK (tipo = 'exportador'),
    ADD CONSTRAINT fk_exportador_cliente FOREIGN KEY (id_cliente, tipo)
        REFERENCES cliente (id_cliente, tipo)
        ON DELETE CASCADE ON UPDATE RESTRICT;

COMMIT;
