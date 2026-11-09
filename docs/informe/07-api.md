# 07 — API REST (P3)

Este documento registra el trabajo de P3 sobre la API REST: contrato OpenAPI,
esqueleto de la aplicación, stubs de integración, manejo central de errores y
las consultas DELETE. La regla de oro del plan (Fase 6) se mantiene en todos
los casos: **la API no recalcula totales, descuentos ni stock**; esas reglas
viven en la base (triggers, columnas generadas y procedimientos).

- Rama de trabajo: `feature/p3-api-fase6`, creada sobre `origin/main` (`0e7b0b8`).
- Alcance autorizado: `api/`, `db/tests/` (solo tests de API), `consultas/delete.sql`
  y este archivo. No se modifican migraciones, seeds, `docker-compose.yml`,
  `scripts/`, `front/`, `README` ni `.env.example`.
- Verificación: base efímera PostgreSQL 16 (contenedor propio, sin credenciales
  de `.env`), migraciones existentes aplicadas en orden con `ON_ERROR_STOP=1`
  y sin alterar sus archivos.

## Tarea A — Contrato OpenAPI alineado con `002_constraints.sql`

### Alcance

`api/openapi.yaml` se redactó antes de que varias correcciones del esquema
llegaran a `main` (por ejemplo R-002, `cliente.descuento` como columna
generada). Esta tarea contrasta enums, rangos y campos de los request schemas
contra los CHECK de `db/migrations/002_constraints.sql` y contra las reglas de
integración de la base, y corrige el contrato.

### Diferencias corregidas

| Campo / schema | Antes | Fuente en la base | Acción |
|---|---|---|---|
| `VinoCreate.presentacion_ml` | enum `[375, 750, 1500]` | `ck_vino_presentacion` — `IN (187, 375, 750, 1500, 3000)` (002:197-198) | Enum con los 5 valores |
| `VinoResumen` / `VinoUpdate.presentacion_ml` | `integer` sin enum | ídem | Enum agregado |
| `anada` (Resumen/Create/Update) | sin límites | `ck_vino_anada` — `BETWEEN 1990 AND 2100` (002:199-200) | `minimum: 1990`, `maximum: 2100` |
| `VinoResumen.graduacion` | sin límites | `ck_vino_graduacion` — `BETWEEN 5 AND 20` (002:195-196) | Rango 5..20 |
| `ComposicionItem.porcentaje` | `minimum: 0` inclusivo | `ck_composicion_porcentaje` — `> 0 AND <= 100` (002:233-234) | `exclusiveMinimum: true` |
| `MaridajeItem.temperatura_servicio` | sin límites | `ck_maridaje_temperatura` — `BETWEEN 0 AND 30` (002:231-232) | Rango 0..30 |
| `tipo_documento` | string libre | `ck_cliente_tipo_documento` — enum (002:187-188) | Schema compartido `TipoDocumento` |
| `ClienteResumen.descuento` | sin límites | `ck_cliente_descuento` — `BETWEEN 0 AND 100` (002:205-206) | Rango 0..100, se mantiene `readOnly` |
| `ClienteCreate.required` | `direccion` opcional | `direccion SET NOT NULL` (002:73-74) | `direccion` pasa a requerida |
| Renglones (comprobante/documento) | `cantidad` sin mínimo | `cantidad > 0` (002:244-247, 256-259) | `minimum: 1` |

### Confirmado sin cambios (ya respetaba la base)

- `POST`/`PUT` de `/clientes` **no** piden `descuento`: es `GENERATED ALWAYS AS
  (fn_descuento_cliente(tipo)) STORED` (001:201) y solo aparece como salida.
- Los POST no piden claves identity (`cod_vino`, `id_cliente`, `nro_comprobante`,
  `nro_solicitud`, `cod_ingreso`): los IDs se recuperan con `RETURNING`.
- Los renglones viajan solo con `(cod_vino, cantidad)`; `precio_unitario`,
  `descuento` y `subtotal` de renglón, y `subtotal`/`descuento`/`total` de
  cabecera, son exclusivamente de respuesta (los calculan los triggers y
  `fn_total_comprobante`).
- `transferencia.fecha_confeccion` no se envía: la fija un trigger (RN-11).
- `EstadoDocumento` (`en_confeccion`, `terminado`, `procesado`) coincide con las
  transiciones que permiten los triggers de 005.
- Enums de `vino.tipo`, `cliente.tipo` y los CUIT `^[0-9]{11}$` coincidían.

### Validación

```
npx @redocly/cli lint api/openapi.yaml
→ exit 0 — "Your API description is valid" (2 warnings preexistentes:
  servidor localhost y `/salud` sin respuesta 4XX)
```

El comando es exactamente el que ejecuta el CI (`.github/workflows/ci.yml`).
Los dos warnings existían antes de esta tarea y no se corrigieron acá para no
mezclar cambios de alcance.

### Limitaciones del contrato

- `fecha_vencimiento > fecha_emision` (permiso de exportación) es una regla
  cruzada entre columnas: no se puede expresar como validación estructural en
  OpenAPI 3.0.3 y queda como documentación; la garantía es
  `ck_permiso_fechas`.
- Las dependencias condicionales de `ClienteCreate` (campos propios de
  `distribuidor`/`exportador`) también se documentan; la base las exige en los
  subtipos.
