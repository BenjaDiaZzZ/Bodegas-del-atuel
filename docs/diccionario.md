# Diccionario de datos

Generado a partir de `information_schema` y `pg_catalog` sobre el esquema
`public` de PostgreSQL 16.15, luego de aplicar `db/migrations/001_esquema.sql`.

- Tablas: **29**
- Columnas: **125**
- Claves primarias: 29
- Claves foraneas: 34

> `001_esquema.sql` define tipos, tablas, PK y FK. Las restricciones
> `CHECK`, `UNIQUE`, `DEFAULT` y `NOT NULL` se agregan en
> `002_constraints.sql`; cuando eso ocurra, este diccionario debe regenerarse.

## Convenciones

- **Tipo**: tipo fisico en PostgreSQL.
- **Nulo**: indica si la columna acepta `NULL`.
- **Default**: valor por defecto; `identity` indica columna generada por identidad
  y, cuando aplica, se aclara el modo (`ALWAYS` o `BY DEFAULT`).
- **Restriccion**: `PK`, `FK -> tabla.columna`, `UNIQUE` o combinacion.
- Los importes usan `NUMERIC(12,2)` y los porcentajes `NUMERIC(5,2)`.

## Resumen de tablas

| Tabla | Columnas |
|---|---:|
| `analisis_calidad` | 6 |
| `auditoria_precio` | 6 |
| `bodega` | 3 |
| `cepa` | 3 |
| `cliente` | 9 |
| `composicion` | 3 |
| `comprobante` | 7 |
| `distribuidor` | 3 |
| `empleado` | 5 |
| `exportador` | 2 |
| `finca` | 5 |
| `ingreso` | 5 |
| `localidad` | 5 |
| `lote_uva` | 7 |
| `maridaje` | 3 |
| `parcela` | 5 |
| `permiso_exportacion` | 4 |
| `renglon_comprobante` | 6 |
| `renglon_ingreso` | 3 |
| `renglon_transferencia` | 3 |
| `sala` | 4 |
| `socio` | 1 |
| `stock_deposito` | 2 |
| `stock_sala` | 3 |
| `transferencia` | 4 |
| `transportista` | 6 |
| `transportista_localidad` | 2 |
| `vino` | 8 |
| `vino_maridaje` | 2 |

## `analisis_calidad`

Analisis de calidad realizados sobre los lotes de uva.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_analisis` | `integer` | No | `identity` | PK | Identificador del analisis de calidad. |
| `nro_lote` | `integer` | Si | `-` | FK -> lote_uva.nro_lote | Lote de uva analizado (FK a lote_uva). |
| `fecha` | `date` | Si | `-` | - | Fecha en que se realizo el analisis. |
| `grado_brix` | `numeric(5,2)` | Si | `-` | - | Medida de azucar del mosto en grados Brix. |
| `ph` | `numeric(4,2)` | Si | `-` | - | Potencial de hidrogeno del mosto. |
| `acidez_total` | `numeric(6,2)` | Si | `-` | - | Acidez total expresada en g/L. |

## `auditoria_precio`

Historial de cambios de precio de los vinos.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_auditoria` | `integer` | No | `identity` | PK | Identificador del registro de auditoria. |
| `cod_vino` | `integer` | Si | `-` | FK -> vino.cod_vino | Vino cuyo precio se modifico (FK a vino). |
| `precio_anterior` | `numeric(12,2)` | Si | `-` | - | Precio de venta anterior al cambio. |
| `precio_nuevo` | `numeric(12,2)` | Si | `-` | - | Precio de venta posterior al cambio. |
| `fecha_hora` | `timestamp` | Si | `-` | - | Fecha y hora del cambio de precio. |
| `usuario` | `varchar(60)` | Si | `-` | - | Usuario que realizo el cambio. |

## `bodega`

Establecimientos elaboradores de vino. La PK es el CUIT.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `cuit` | `cuit_dom` | No | `-` | PK | CUIT de la bodega (PK). |
| `razon_social` | `varchar(120)` | Si | `-` | - | Razon social de la bodega. |
| `domicilio` | `varchar(150)` | Si | `-` | - | Domicilio legal de la bodega. |

## `cepa`

Catalogo de variedades de uva plantadas en las parcelas.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_cepa` | `integer` | No | `identity` | PK | Identificador de la cepa. |
| `nombre` | `varchar(60)` | Si | `-` | - | Nombre de la variedad de uva. |
| `tipo` | `varchar(10)` | Si | `-` | - | Tipo de uva: tinta o blanca. |

## `cliente`

Supertipo de cliente: socio, distribuidor o exportador.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_cliente` | `integer` | No | `identity` | PK | Identificador del cliente. |
| `nombre` | `varchar(120)` | Si | `-` | - | Apellido y nombre o razon social del cliente. |
| `tipo` | `varchar(15)` | Si | `-` | - | Tipo de cliente: socio, distribuidor o exportador. |
| `tipo_documento` | `varchar(10)` | Si | `-` | - | Tipo de documento del cliente. |
| `nro_documento` | `varchar(20)` | Si | `-` | - | Numero de documento del cliente. |
| `direccion` | `varchar(150)` | Si | `-` | - | Direccion del cliente. |
| `id_localidad` | `integer` | Si | `-` | FK -> localidad.id_localidad | Localidad del cliente (FK a localidad). |
| `fecha_alta` | `date` | Si | `-` | - | Fecha de alta del cliente. |
| `descuento` | `numeric(5,2)` | Si | `-` | - | Porcentaje de descuento asignado al cliente. |

## `composicion`

Relacion N:M entre vino y cepa con el porcentaje de cada cepa.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `cod_vino` | `integer` | No | `-` | PK<br>FK -> vino.cod_vino | Vino que compone la mezcla (FK a vino). |
| `id_cepa` | `integer` | No | `-` | PK<br>FK -> cepa.id_cepa | Cepa que compone la mezcla (FK a cepa). |
| `porcentaje` | `numeric(5,2)` | Si | `-` | - | Porcentaje de la cepa en el vino. La suma debe ser 100. |

## `comprobante`

Comprobantes de venta con subtotal, descuento y total.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `nro_comprobante` | `integer` | No | `identity` | PK | Numero del comprobante de venta. |
| `fecha` | `date` | Si | `-` | - | Fecha de la venta. |
| `id_cliente` | `integer` | Si | `-` | FK -> cliente.id_cliente | Cliente que realizo la compra (FK a cliente). |
| `id_sala` | `integer` | Si | `-` | FK -> sala.id_sala | Sala donde se realizo la venta (FK a sala). |
| `subtotal` | `numeric(12,2)` | Si | `-` | - | Suma de los renglones antes del descuento. |
| `descuento` | `numeric(12,2)` | Si | `-` | - | Importe de descuento aplicado al comprobante. |
| `total` | `numeric(12,2)` | Si | `-` | - | Importe total del comprobante. |

## `distribuidor`

Subtipo de cliente: distribuidor con zona y habilitacion. PK = FK a cliente.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_cliente` | `integer` | No | `-` | PK<br>FK -> cliente.id_cliente | Cliente distribuidor (PK y FK a cliente). |
| `zona_cobertura` | `varchar(80)` | Si | `-` | - | Zona geografica de cobertura. |
| `nro_habilitacion` | `varchar(30)` | Si | `-` | - | Numero de habilitacion del distribuidor. |

## `empleado`

Empleados de las salas de venta. La PK es el CUIT.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `cuit` | `cuit_dom` | No | `-` | PK | CUIT del empleado (PK). |
| `nombre` | `varchar(120)` | Si | `-` | - | Nombre completo del empleado. |
| `fecha_ingreso` | `date` | Si | `-` | - | Fecha de ingreso laboral. |
| `salario` | `numeric(12,2)` | Si | `-` | - | Salario del empleado. |
| `id_sala` | `integer` | Si | `-` | FK -> sala.id_sala | Sala en la que trabaja (FK a sala). |

## `exportador`

Subtipo de cliente: exportador con pais de destino. PK = FK a cliente.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_cliente` | `integer` | No | `-` | PK<br>FK -> cliente.id_cliente | Cliente exportador (PK y FK a cliente). |
| `pais_destino_principal` | `varchar(60)` | Si | `-` | - | Pais de destino principal de las exportaciones. |

## `finca`

Establecimientos vitivinicola con superficie y ubicacion.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_finca` | `integer` | No | `identity` | PK | Identificador de la finca. |
| `nombre` | `varchar(80)` | Si | `-` | - | Nombre de la finca. |
| `superficie_hectareas` | `numeric(10,2)` | Si | `-` | - | Superficie total de la finca en hectareas. |
| `departamento` | `varchar(80)` | Si | `-` | - | Departamento donde se ubica la finca. |
| `provincia` | `varchar(50)` | Si | `-` | - | Provincia donde se ubica la finca. |

## `ingreso`

Ingresos de vino con estado, transportista y bodega de origen.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `cod_ingreso` | `integer` | No | `identity` | PK | Codigo de ingreso. |
| `fecha` | `date` | Si | `-` | - | Fecha del ingreso. |
| `estado` | `estado_documento` | Si | `-` | - | Estado del documento: en_confeccion, terminado o procesado. |
| `id_transportista` | `integer` | Si | `-` | FK -> transportista.id_transportista | Transportista que realizo el ingreso (FK a transportista). |
| `cuit_bodega` | `cuit_dom` | Si | `-` | FK -> bodega.cuit | Bodega de origen del ingreso (FK a bodega). |

## `localidad`

Catalogo geografico de localidades con su responsable comercial regional.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_localidad` | `integer` | No | `identity` | PK | Identificador de la localidad. |
| `codigo_postal` | `varchar(10)` | Si | `-` | - | Codigo postal de la localidad. |
| `nombre` | `varchar(80)` | Si | `-` | - | Nombre de la localidad. |
| `provincia` | `varchar(50)` | Si | `-` | - | Provincia de la localidad. |
| `encargado_regional` | `varchar(80)` | Si | `-` | - | Responsable comercial regional de la localidad. |

## `lote_uva`

Lotes de uva cosechados en una parcela y campania.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `nro_lote` | `integer` | No | `-` | PK | Numero de lote de uva. |
| `id_finca` | `integer` | Si | `-` | FK -> parcela.id_finca | Finca de la parcela de origen (parte de FK compuesta a parcela). |
| `nro_parcela` | `integer` | Si | `-` | FK -> parcela.nro_parcela | Numero de parcela de origen (parte de FK compuesta a parcela). |
| `campania` | `integer` | Si | `-` | - | Campania o ano de cosecha. |
| `fecha_cosecha` | `date` | Si | `-` | - | Fecha de cosecha del lote. |
| `kilos_cosechados` | `numeric(12,2)` | Si | `-` | - | Kilos cosechados en el lote. |
| `cuit_bodega` | `cuit_dom` | Si | `-` | FK -> bodega.cuit | Bodega destino del lote (FK a bodega). |

## `maridaje`

Sugerencias de acompanamiento y temperatura de servicio.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_maridaje` | `integer` | No | `identity` | PK | Identificador del maridaje. |
| `nombre` | `varchar(60)` | Si | `-` | - | Nombre o descripcion del maridaje. |
| `temperatura_servicio` | `numeric(4,1)` | Si | `-` | - | Temperatura de servicio sugerida en grados Celsius. |

## `parcela`

Entidad debil de finca: parcela identificada por finca y numero.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_finca` | `integer` | No | `-` | PK<br>FK -> finca.id_finca | Finca a la que pertenece la parcela (PK y FK a finca). |
| `nro_parcela` | `integer` | No | `-` | PK | Numero de parcela dentro de la finca (PK). |
| `superficie_hectareas` | `numeric(10,2)` | Si | `-` | - | Superficie de la parcela en hectareas. |
| `anio_plantacion` | `integer` | Si | `-` | - | Ano de plantacion de la parcela. |
| `id_cepa` | `integer` | Si | `-` | FK -> cepa.id_cepa | Cepa plantada en la parcela (FK a cepa). |

## `permiso_exportacion`

Entidad debil de exportador: permisos con emision y vencimiento.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_cliente` | `integer` | No | `-` | PK<br>FK -> exportador.id_cliente | Exportador titular del permiso (PK y FK a exportador). |
| `cod_permiso` | `varchar(20)` | No | `-` | PK | Codigo del permiso de exportacion (PK). |
| `fecha_emision` | `date` | Si | `-` | - | Fecha de emision del permiso. |
| `fecha_vencimiento` | `date` | Si | `-` | - | Fecha de vencimiento del permiso. |

## `renglon_comprobante`

Renglones N:M de comprobante y vino con precio y subtotal.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `nro_comprobante` | `integer` | No | `-` | PK<br>FK -> comprobante.nro_comprobante | Comprobante al que pertenece el renglon (PK y FK). |
| `cod_vino` | `integer` | No | `-` | PK<br>FK -> vino.cod_vino | Vino vendido en el renglon (PK y FK a vino). |
| `cantidad` | `integer` | Si | `-` | - | Cantidad de botellas vendidas. |
| `precio_unitario` | `numeric(12,2)` | Si | `-` | - | Precio unitario aplicado al momento de la venta. |
| `descuento` | `numeric(12,2)` | Si | `-` | - | Importe de descuento aplicado al renglon. |
| `subtotal` | `numeric(12,2)` | Si | `-` | - | Subtotal del renglon. |

## `renglon_ingreso`

Renglones N:M de ingreso y vino con cantidad.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `cod_ingreso` | `integer` | No | `-` | PK<br>FK -> ingreso.cod_ingreso | Ingreso al que pertenece el renglon (PK y FK). |
| `cod_vino` | `integer` | No | `-` | PK<br>FK -> vino.cod_vino | Vino ingresado (PK y FK a vino). |
| `cantidad` | `integer` | Si | `-` | - | Cantidad ingresada. |

## `renglon_transferencia`

Renglones N:M de transferencia y vino con cantidad.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `nro_solicitud` | `integer` | No | `-` | PK<br>FK -> transferencia.nro_solicitud | Transferencia a la que pertenece el renglon (PK y FK). |
| `cod_vino` | `integer` | No | `-` | PK<br>FK -> vino.cod_vino | Vino transferido (PK y FK a vino). |
| `cantidad` | `integer` | Si | `-` | - | Cantidad transferida. |

## `sala`

Salas de venta con direccion, dia de cierre y localidad.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_sala` | `integer` | No | `identity` | PK | Identificador de la sala de venta. |
| `direccion` | `varchar(150)` | Si | `-` | - | Direccion de la sala (calle y numero). |
| `dia_cierre_semanal` | `smallint` | Si | `-` | - | Dia de cierre semanal (1 = lunes ... 7 = domingo). |
| `id_localidad` | `integer` | Si | `-` | FK -> localidad.id_localidad | Localidad de la sala (FK a localidad). |

## `socio`

Subtipo de cliente: socio del club. PK = FK a cliente.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_cliente` | `integer` | No | `-` | PK<br>FK -> cliente.id_cliente | Cliente socio del club (PK y FK a cliente). |

## `stock_deposito`

Stock de deposito por vino. Relacion 1:1 con vino.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `cod_vino` | `integer` | No | `-` | PK<br>FK -> vino.cod_vino | Vino en deposito (PK y FK a vino). |
| `cantidad` | `integer` | Si | `-` | - | Cantidad disponible en deposito. |

## `stock_sala`

Stock disponible por sala y vino. Relacion N:M con cantidad.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_sala` | `integer` | No | `-` | PK<br>FK -> sala.id_sala | Sala del stock (PK y FK a sala). |
| `cod_vino` | `integer` | No | `-` | PK<br>FK -> vino.cod_vino | Vino del stock (PK y FK a vino). |
| `cantidad` | `integer` | Si | `-` | - | Cantidad disponible en la sala. |

## `transferencia`

Solicitudes de transferencia con sala, fecha y estado.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `nro_solicitud` | `integer` | No | `identity` | PK | Numero de solicitud de transferencia. |
| `id_sala` | `integer` | Si | `-` | FK -> sala.id_sala | Sala solicitante (FK a sala). |
| `fecha_confeccion` | `date` | Si | `-` | - | Fecha de confeccion de la transferencia. |
| `estado` | `estado_documento` | Si | `-` | - | Estado del documento: en_confeccion, terminado o procesado. |

## `transportista`

Empresas que trasladan los ingresos de uva o vino.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_transportista` | `integer` | No | `identity` | PK | Identificador del transportista. |
| `razon_social` | `varchar(120)` | Si | `-` | - | Razon social del transportista. |
| `cuit` | `cuit_dom` | Si | `-` | - | CUIT del transportista. |
| `email` | `varchar(120)` | Si | `-` | - | Correo electronico de contacto. |
| `telefono` | `varchar(30)` | Si | `-` | - | Telefono de contacto. |
| `domicilio` | `varchar(150)` | Si | `-` | - | Domicilio del transportista. |

## `transportista_localidad`

Relacion N:M entre transportista y localidad cubierta.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `id_transportista` | `integer` | No | `-` | PK<br>FK -> transportista.id_transportista | Transportista (PK y FK a transportista). |
| `id_localidad` | `integer` | No | `-` | PK<br>FK -> localidad.id_localidad | Localidad cubierta (PK y FK a localidad). |

## `vino`

Vinos comercializados, con tipo, anada, presentacion y precio.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `cod_vino` | `integer` | No | `identity (ALWAYS)` | PK | Codigo identificador del vino. |
| `nombre_comercial` | `varchar(120)` | Si | `-` | - | Nombre comercial del vino. |
| `tipo` | `varchar(12)` | Si | `-` | - | Tipo de vino: tinto, blanco, rosado o espumante. |
| `anada` | `integer` | Si | `-` | - | Anada o ano de cosecha del vino. |
| `presentacion_ml` | `integer` | Si | `-` | - | Volumen de la presentacion en mililitros. |
| `graduacion` | `numeric(4,2)` | Si | `-` | - | Graduacion alcoholica del vino. |
| `precio_venta` | `numeric(12,2)` | Si | `-` | - | Precio de venta vigente. |
| `cuit_bodega` | `cuit_dom` | Si | `-` | FK -> bodega.cuit | Bodega que elabora el vino (FK a bodega). |

## `vino_maridaje`

Relacion N:M entre vino y maridaje.

| Columna | Tipo | Nulo | Default | Restriccion | Descripcion funcional |
|---|---|---|---|---|---|
| `cod_vino` | `integer` | No | `-` | PK<br>FK -> vino.cod_vino | Vino (PK y FK a vino). |
| `id_maridaje` | `integer` | No | `-` | PK<br>FK -> maridaje.id_maridaje | Maridaje (PK y FK a maridaje). |

## Verificacion

La cantidad de filas de este documento debe coincidir con:

```sql
SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public';
```

Resultado esperado para `001_esquema.sql`: **125** columnas en **29** tablas.
