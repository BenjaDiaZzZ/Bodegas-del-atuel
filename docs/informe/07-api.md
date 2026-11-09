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

## Tarea B — Esqueleto FastAPI (plan 6.1)

### Alcance

Estructura inicial de la API en `api/` con FastAPI + psycopg 3 + `psycopg_pool`,
SQL puro y parametrizado (sin ORM ni query builders), conexión exclusivamente
con el rol `app_rw` mediante variables de entorno, y `GET /salud` ejecutando un
`SELECT 1` real contra PostgreSQL.

| Archivo | Rol |
|---|---|
| `api/app/main.py` | App de FastAPI (factory `create_app`), registro de routers y ciclo de vida del pool |
| `api/app/config.py` | Settings desde variables de entorno (dataclass, sin dependencias nuevas) |
| `api/app/db.py` | Pool `psycopg_pool.ConnectionPool` y helper de conexión |
| `api/app/repos/salud.py` | Única consulta del esqueleto: `SELECT 1` (una función por consulta) |
| `api/app/routers/salud.py` | `GET /salud` con respuesta `Salud` de OpenAPI |
| `api/tests/test_salud.py`, `test_db.py` | Pruebas del endpoint y de conectividad |
| `api/requirements.txt` | Dependencias pinneadas (runtime y dev-test) |
| `api/pytest.ini` | Config para correr `python -m pytest api/tests` desde la raíz |

### Variables de entorno

| Variable | Default | Requerida | Uso |
|---|---|---|---|
| `POSTGRES_HOST` | `localhost` | no | Host de PostgreSQL |
| `POSTGRES_PORT` | `5432` | no | Puerto |
| `POSTGRES_DB` | — | sí | Base de datos |
| `DB_USER` | `app_rw` | no | Rol de aplicación (nunca el propietario) |
| `DB_PASSWORD` | — | sí | Contraseña de `app_rw` (misma variable que usa `scripts/set_role_passwords.sh`) |

`.env.example` está fuera del alcance autorizado de esta entrega, por lo que no
se editó. **Propuesta de incorporación** (para quien tenga el archivo a cargo):

```dotenv
# Host de PostgreSQL para la API (default: localhost).
POSTGRES_HOST=localhost
# Rol de aplicación de privilegios limitados que usa la API (default: app_rw).
DB_USER=app_rw
```

### Decisiones

- `/salud` responde el shape `Salud` documentado en OpenAPI
  (`status`, `db`, `version`, `timestamp`) con datos reales de la conexión; la
  versión la informa el propio servidor PostgreSQL.
- Si la base no está disponible, responde `503` con el schema `Error`
  (`codigo: DB_UNAVAILABLE`) sin filtrar credenciales ni detalles internos.
- El SQL vive solo en `repos/`; los routers no contienen consultas (adelanta la
  separación que pide la tarea 6.3).
- El pool se abre/cierra con el ciclo de vida de la aplicación; la fábrica
  `create_app(settings)` permite inyectar configuración en las pruebas.

### Pruebas (TDD)

- **RED**: `pytest api/tests` → 2 errores de colección (`ModuleNotFoundError: No
  module named 'app'`), la aplicación aún no existía.
- **GREEN**: `6 passed` sobre PostgreSQL 16 efímero (migraciones 001–007
  aplicadas sin modificarlas, conexión como `app_rw`).
- **Smoke en vivo**: `uvicorn app.main:app --app-dir api` + `curl /salud` →
  `HTTP/1.1 200 OK` con `{"status":"ok","db":true,"version":"PostgreSQL 16.15",...}`.
- Cobertura de los negativos: `POSTGRES_DB` faltante (falla rápido al arrancar)
  y base inaccesible (`503` sin contraseña en la respuesta).

## Tarea C — Stubs de todos los endpoints (plan 6.2)

### Alcance

Las 25 operaciones documentadas en `api/openapi.yaml` quedan respondiendo con
payloads fijos que respetan sus schemas, para que P4 pueda integrar el front
sin esperar a la implementación real (6.3–6.10). Cada handler lleva un
comentario `# TODO(6.x)` con la tarea del plan que lo va a implementar.

| Recurso | Operaciones | TODO | Estado éxito |
|---|---|---|---|
| Vinos | GET /vinos, GET /vinos/{cod} | 6.5 | 200 |
| Vinos | POST /vinos, PUT /vinos/{cod} | 6.6 | 201 / 200 |
| Vinos | DELETE /vinos/{cod} | 6.6 | 204 |
| Clientes | GET /clientes, GET /clientes/{id} | 6.7 | 200 |
| Clientes | POST /clientes, PUT /clientes/{id} | 6.7 | 201 / 200 |
| Clientes | DELETE /clientes/{id} | 6.7 | 204 |
| Comprobantes | POST /comprobantes, GET /comprobantes/{nro} | 6.8 | 201 / 200 |
| Transferencias | POST /transferencias y /{nro}/renglones | 6.9 | 201 |
| Transferencias | POST /{nro}/terminar, /{nro}/procesar | 6.9 | 200 |
| Ingresos | POST /ingresos y /{cod}/renglones | 6.9 | 201 |
| Ingresos | POST /{cod}/terminar, /{cod}/procesar | 6.9 | 200 |
| Reportes | top-vinos, ventas-por-sala, vinos-sin-stock, transportista-activo, trazabilidad/{cod} | 6.10 | 200 |

### Decisiones

- `api/app/schemas.py` centraliza los modelos Pydantic que espejan los schemas
  de OpenAPI: FastAPI valida que cada respuesta fija respete el contrato.
- Los ejemplos de respuesta salen de los `example` del propio OpenAPI; los
  detalles por id repiten el id del path cuando el schema lo incluye.
- Los stubs **no** tocan el pool ni escriben SQL (esas tareas son 6.3+): cero
  lógica de negocio adelantada.
- `api/tests/test_stubs.py` es un test data-driven que llama a las 26 rutas
  (25 + `/salud`) y verifica el status documentado y las claves del schema.

### Pruebas

- **RED**: las rutas aún no existían → `25 failed, 1 passed` (ejemplo:
  `GET /vinos` respondía 404).
- **GREEN**: `32 passed` (6 previas + 26 de cobertura) sobre PostgreSQL 16
  efímero.
- `npx @redocly/cli lint api/openapi.yaml` sin regresiones (exit 0, los mismos
  2 warnings preexistentes).

### Observaciones sobre el contrato (reportadas, no corregidas)

- El texto informativo de OpenAPI dice «~20 rutas» pero el documento define
  **25 operaciones**; discrepancia cosmética.
- `DELETE /vinos/{cod}` documenta `503` pero `DELETE /clientes/{id}` no:
  inconsistencia menor a alinear cuando se implementen (6.6/6.7).
