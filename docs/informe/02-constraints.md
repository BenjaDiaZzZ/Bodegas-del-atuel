# Tarea 2.1 — Constraints de integridad (`002_constraints.sql`)

## Alcance

`db/migrations/002_constraints.sql` se aplica sobre `001_esquema.sql` y agrega
`NOT NULL`, `UNIQUE`, `CHECK` y `DEFAULT` sin modificar las claves primarias.
Las únicas FK que se redefinen son las tres de los subtipos de cliente, para
incluir `tipo` en la jerarquía.

## Mínimos de la consigna

| Requisito | Mínimo | Implementado |
|---|---:|---:|
| UNIQUE adicionales a las PK | 4 | 10 |
| CHECK | 8 | 38 (37 de tabla + 1 de dominio) |
| CHECK cruzado entre columnas | 1 | 2 |
| DEFAULT | 3 | 12 |

Los dos CHECK cruzados son `ck_permiso_fechas`
(`fecha_vencimiento > fecha_emision`) y `ck_comprobante_total`
(`total = subtotal - descuento`).

## Decisiones de diseño

### Descuentos

Hay dos columnas homónimas con semántica distinta:

- `cliente.descuento` es un **porcentaje**: `ck_cliente_descuento` lo limita a
  `0..100`.
- `comprobante.descuento` y `renglon_comprobante.descuento` son **importes**
  (`NUMERIC(12,2)`): sus CHECK exigen `>= 0`. En particular,
  `ck_renglon_comprobante_descuento` ya no usa `BETWEEN 0 AND 100`, porque un
  descuento de $150 es válido.

### Jerarquía de clientes

Los subtipos `socio`, `distribuidor` y `exportador` tienen una FK compuesta
`(id_cliente, tipo)` contra `cliente(id_cliente, tipo)` y un CHECK que fija su
propio tipo. Esa FK usa `ON DELETE CASCADE ON UPDATE RESTRICT`: un `CASCADE`
desde `cliente` intentaría copiar el nuevo `tipo` al subtipo y violaría su
CHECK. Con `RESTRICT`, el cambio de tipo se bloquea mientras exista la fila del
subtipo; para cambiarlo hay que borrar primero esa fila.

### Código postal

`ck_localidad_codigo_postal` valida el formato de 4 dígitos del Anexo B con
`codigo_postal ~ '^[0-9]{4}$'`. Si se adopta CPA, el patrón se amplía a
`'^([0-9]{4}|[A-Z][0-9]{4}[A-Z]{3})$'` y se normaliza a mayúsculas.

### Fechas

Ningún CHECK usa `CURRENT_DATE` ni funciones no determinísticas. Los `DEFAULT`
con `CURRENT_DATE` o `now()` son válidos porque no son restricciones y no se
reevalúan al restaurar un backup. Las reglas que dependen de la fecha actual
quedan para los triggers de `005_triggers.sql`.

## Verificación

La migración se aplicó sobre una base vacía con PostgreSQL 16, ejecutando
`001_esquema.sql` y luego `002_constraints.sql` con `ON_ERROR_STOP=1`. Los
tests de `db/tests/db_tests.sql` pasaron dos veces consecutivas con `EXIT=0`.
El detalle está en `docs/informe/02-tests-constraints.md`.

## Trazabilidad de la tarea 2.1

| Requisito | Restricciones | Caso de prueba |
|---|---|---|
| UNIQUE de vino | `uq_vino_nombre_anada_presentacion` | 5 |
| UNIQUE de cliente | `uq_cliente_tipo_nro_documento` | 6 |
| CHECK de graduación | `ck_vino_graduacion` | 1 |
| CHECK de precio | `ck_vino_precio_venta` | 2 |
| CHECK cruzado de permiso | `ck_permiso_fechas` | 3 |
| CHECK cruzado de comprobante | `ck_comprobante_total` | 4 |
| CHECK de stock | `ck_stock_sala_cantidad` | 7 |
| DEFAULT de estado | `ingreso.estado` | 8 |
| Descuento como importe | `ck_renglon_comprobante_descuento` | 9 |
| Jerarquía de cliente | `fk_*_cliente` + `ON UPDATE RESTRICT` | 10 |
| Formato de código postal | `ck_localidad_codigo_postal` | 11 |
