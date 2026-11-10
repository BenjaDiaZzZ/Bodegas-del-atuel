# 07 — API REST (P3)

Este documento registra el trabajo de P3 sobre la API REST: contrato OpenAPI,
esqueleto de la aplicación, stubs de integración, manejo central de errores y
las consultas DELETE. La regla de oro del plan (Fase 6) se mantiene en todos
los casos: **la API no recalcula totales, descuentos ni stock**; esas reglas
viven en la base (triggers, columnas generadas y procedimientos).

- Rama de trabajo: `feature/p3-api-fase6`, creada sobre `origin/main` (`0e7b0b8`).
- Alcance autorizado: `api/`, `db/tests/` (solo tests de API), `consultas/delete.sql`
  y este archivo. No se modifican migraciones, seeds, `docker-compose.yml`,
  `scripts/`, `front/` ni `README`. (`.env.example` se actualizó luego con
  `POSTGRES_SSLMODE`, por autorización expresa para el despliegue en Aiven.)
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
| `POSTGRES_SSLMODE` | `prefer` | no | Modo SSL (libpq) de la conexión de la API; usar `require` en el despliegue en Aiven |

Para el despliegue en Aiven (producción), la API debe conectarse con
`POSTGRES_SSLMODE=require` usando el rol `app_rw`; en local o Docker sin SSL se
mantiene el default `prefer`, que no rompe PostgreSQL local.

`.env.example` quedó fuera del alcance autorizado de la entrega de la fase 6.
Posteriormente se incorporó `POSTGRES_SSLMODE` al archivo (ver bloque abajo),
con autorización expresa para el despliegue en Aiven. Siguen **pendientes**
`POSTGRES_HOST` y `DB_USER` (propuesta para quien tenga el archivo a cargo):

```dotenv
# Host de PostgreSQL para la API (default: localhost).
POSTGRES_HOST=localhost
# Rol de aplicación de privilegios limitados que usa la API (default: app_rw).
DB_USER=app_rw
# Modo SSL de la conexión de la API (libpq). Default: prefer, compatible con
# PostgreSQL local sin SSL. En el despliegue en Aiven (producción) usar:
# POSTGRES_SSLMODE=require
POSTGRES_SSLMODE=prefer
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

## Tarea D — Manejo central de errores SQLSTATE (plan 6.4)

### Alcance

Un único punto de conversión PostgreSQL → HTTP (`api/app/errors.py`) usado
tanto por el helper de transacciones como por los exception handlers de
FastAPI. El shape de respuesta es el schema `Error` del contrato (`codigo`,
`mensaje`, `detalle`, `regla`).

| SQLSTATE | HTTP | Comportamiento |
|---|---|---|
| `23505` unique_violation | 409 | `codigo` = SQLSTATE, `detalle` del diag |
| `23503` foreign_key_violation | 409 o 422 | criterio abajo |
| `23514` check_violation | 422 | |
| `23502` not_null_violation | 422 | |
| `P0001` raise_exception | 409 | conserva el mensaje `[RN-xx]` y extrae `regla` |
| `P0002` no_data_found | 404 | |
| `22P02` invalid_text_representation | 400 | |
| `40001` / `40P01` serialización / deadlock | 503 | el mensaje indica que la operación puede reintentarse |
| `42501` insufficient_privilege | 500 | cuerpo genérico, sin detalles internos |
| desconocido | 500 | cuerpo genérico, sin fuga de texto crudo |

### Criterio para `23503` (elegido y documentado)

Se clasifica por la **dirección de la violación referencial**, leída del
`detail` de PostgreSQL (fallback: `message_primary`):

- «is still referenced from table» / «update or delete on table …» → la
  operación está bloqueada por filas dependientes → **409 Conflict**.
- «is not present in table» / «insert or update on table …» → el request
  referencia un padre inexistente → **422**.
- Texto no reconocido → default documentado **422**.

Los dos textos estándar están en inglés en el servidor de PostgreSQL; un
servidor localizado cae en el fallback documentado (anotado en el docstring).

### Transacciones: el COMMIT va dentro del manejo de errores

`tg_composicion_cien` (RN-05) es un constraint trigger `DEFERRABLE INITIALLY
DEFERRED`: su `P0001 '[RN-05] …'` aparece en el **COMMIT**, no en el INSERT.
Por eso `transaction()` en `api/app/db.py` ejecuta `BEGIN … COMMIT` dentro del
`try`, y cualquier `psycopg.Error` — incluido el que levanta el propio COMMIT —
pasa por el mapeador central (con `ROLLBACK` de seguridad).

### Corrección del hallazgo de revisión R3-01

`GET /salud` también captura el `RuntimeError` del repositorio (servidor sin
`server_version`) y responde el mismo `503` saneado, en lugar de un 500 no
documentado.

### Pruebas (TDD)

- **RED**: `ImportError` al importar `map_db_error` / `transaction` /
  `DatabaseHttpError` (los módulos aún no existían).
- **GREEN**: `57 passed` en total, de los cuales 25 son nuevas:
  - `api/tests/test_errors.py` — 20 pruebas **sin base de datos** sobre la
    tabla completa de mapeo (incluye el criterio de `23503` en sus tres ramas,
    la extracción de `regla` para `P0001`, el mensaje de reintento en 503 y la
    ausencia de fugas en 500).
  - `api/tests/test_errors_pg.py` — 4 pruebas **reales contra PostgreSQL 16**:
    `fn_descuento_cliente('tipo_invalido')` → 409 con `regla: RN-06`;
    **RN-05 diferido**: el INSERT de vino + composición (porcentajes ≠ 100)
    pasa, y el `COMMIT` devuelve `P0001 '[RN-05] …'` mapeado a 409 con
    `regla: RN-05` (evidencia directa de que el COMMIT está dentro del
    manejo); duplicado de `vino` → 409/`23505`; `CALL sp_procesar_ingreso(999999)`
    → 404/`P0002`.
  - regresión de `/salud` para el camino `RuntimeError` → 503.
- Fixtures creadas como superusuario (el rol `app_rw` no puede insertar
  `bodega`/`cepa`); el ejercicio de las sentencias corre como `app_rw` y el
  teardown deja los conteos en 0.

## Tarea E — `consultas/delete.sql` (plan 5.3)

### Cambio: D3 filtra por antigüedad con la función

La consigna 5.3 pide filtrar «por antigüedad con la función». D3 usaba
aritmética de fechas (`fecha_ingreso > CURRENT_DATE - INTERVAL '2 years'`) en
sus tres sentencias (control previo, DELETE y control posterior) y ahora usa
`fn_antiguedad_anios(e.fecha_ingreso) < 2`. Es la única modificación del
archivo: las migraciones no se tocaron para conseguir ningún resultado.

### Prueba real de D5 en PostgreSQL 16 efímero

Fixture construido con el flujo normal de la base (sin saltarse triggers):
ingreso en `en_confeccion` con `fecha = CURRENT_DATE - 400 días`, un renglón,
`UPDATE … SET estado = 'terminado'` y `CALL sp_procesar_ingreso(cod)` hasta
llegar a `procesado` (verificado antes de ejecutar D5).

**Resultado real de `DELETE FROM ingreso WHERE estado = 'procesado' AND fecha <
CURRENT_DATE - INTERVAL '365 days'`:**

- **`DELETE 1` — el borrado funciona**, sin SQLSTATE ni regla que lo bloquee.
- El `renglon_ingreso` desapareció por `ON DELETE CASCADE` (verificado: 0
  renglones después del DELETE, dentro de la misma transacción).
- **RN-12 no bloquea la cascada**: `tg_renglon_ingreso_biud` salta la
  validación cuando la cabecera ya no existe (`NOT FOUND → RETURN OLD`,
  005:422-428) y la cascada se ejecuta después de borrar la cabecera. La nota
  de integración con P1 que quedaba abierta en el propio archivo y en la guía
  de estudio **puede cerrarse: no hace falta una excepción de P1 para D5**.
- La consulta de control posterior devolvió 0.

### Resultado real de D3

- `DELETE 2` (los dos empleados con menos de dos años: −300 y −60 días);
  el empleado con 1000 días de antigüedad **no** se borró.
- Sin errores de FK RESTRICT (`fk_empleado_sala` no interviene al borrar
  empleados); control posterior en 0.

### Pasada completa del archivo (D1–D6)

Ejecución única con cada bloque en su `BEGIN … ROLLBACK` (sin destruir datos):
los 6 bloques terminaron sin `ERROR`. D2 borró 2 cepas huérfanas; D1, D4 y D6
devolvieron `DELETE 0` porque el dataset efímero no tiene comprobantes de
clientes con esa antigüedad; no se observó ninguna FK RESTRICT bloqueando
borrados en este dataset (la restricción a anotar, si aparece, sería con el
dataset completo de seeds).

### Limpieza

El fixture se borró al terminar (orden FK-safe) y los 9 controles de conteo
quedaron en 0, incluido el `stock_deposito` que había generado el
procedimiento.

## Cierre de la entrega

### Estado de las tareas

| Tarea | Estado | Motivo / evidencia |
|---|---|---|
| A — Contrato OpenAPI vs 002 | Hecha | Commit `5d68a96`; lint CI en verde |
| B — Esqueleto FastAPI (6.1) | Hecha | Commit `6ee1b4e`; `/salud` real contra PG16 |
| C — Stubs (6.2) | Hecha | Commit `ead7fa3` + `d876a6f`; 25 operaciones cubiertas |
| D — Errores SQLSTATE (6.4) | Hecha | Commit `2d1e112`; 57 tests, RN-05 probado en COMMIT |
| E — DELETE (5.3) | Hecha | D3 con `fn_antiguedad_anios`; D5 probado en PG16 real |

### Commits de la rama `feature/p3-api-fase6`

| Commit | Contenido |
|---|---|
| `5d68a96` | `fix(api): align OpenAPI contract with 002 CHECK constraints` |
| `6ee1b4e` | `feat(api): add FastAPI skeleton with real /salud check (6.1)` |
| `ead7fa3` | `feat(api): stub all OpenAPI routes for front integration (6.2)` |
| `d876a6f` | `test(api): assert stub item and detail response shapes (review advisories)` |
| `2d1e112` | `feat(api): central SQLSTATE to HTTP error mapping (6.4)` |
| (este) | `fix(consultas): D3 filters tenure with fn_antiguedad_anios (5.3)` |

### Pruebas ejecutadas y resultados reales

- `pytest api/tests` → **57 passed** (6 del esqueleto, 26 de stubs, 20 del
  mapeo de errores sin base, 4 reales contra PostgreSQL 16, 1 de regresión de
  `/salud`). Última corrida sobre la base efímera con migraciones 001–007 sin
  modificar.
- `npx @redocly/cli lint api/openapi.yaml` → exit 0 (2 warnings preexistentes).
- Smoke en vivo `uvicorn` + `curl /salud` → 200 con `PostgreSQL 16.15`.
- D3/D5 y pasada D1–D6 sobre PostgreSQL 16 efímero (resultados arriba).
- Revisiones RDD: 3 candidatos (A+B, C, D) revisados con lente
  `review-reliability` y **aprobados**; autoridades quemadas. Los hallazgos no
  bloqueantes quedan listados más abajo.

### Queda pendiente del plan P3

- 6.3 capa de acceso a datos (los `TODO(6.x)` de los stubs), 6.5–6.10
  implementación real de endpoints, 6.11 suite ampliada (mínimo 8 pruebas con
  3 que violen reglas — ya hay más de 3, pero el mínimo del plan se cierra con
  la implementación real), 6.12 demo de inyección SQL, 6.13 Dockerfile y
  coherencia final OpenAPI/rutas, 9.2 consolidación del informe final.
- Hallazgos no bloqueantes de las revisiones: todos triados y cerrados en la
  sección «Cierre de advisories de revisión» (R3-4 aceptado; el resto
  corregido con pruebas de regresión). R3-01 ya se había corregido en la tarea
  D. R3-04 (pin del catch de `/salud` sin depender de la jerarquía del pool)
  quedó fuera del alcance pedido; los tests nuevos del seam de errores lo
  cubren parcialmente.

### Cierre de advisories de revisión (2026-11-09)

Revisión acotada de los siete advisories pendientes. Cada uno se verificó
contra el código vigente, se clasificó y (si correspondía a P3) se corrigió
con su prueba de regresión.

| Advisory | ¿Vigente? | Clasificación | Resolución |
|---|---|---|---|
| R3-02 — `create_app()` leía el entorno en el import | Sí | **corregido** | `Settings.from_env()` se resuelve recién al arrancar el lifespan; `import app.main` ya no exige variables de entorno (el entrypoint `uvicorn app.main:app` no cambia y sin entorno falla rápido al arrancar). Prueba: import en subproceso con el entorno vacío. |
| R3-03 — `POSTGRES_PORT` no numérico sin nombre de variable | Sí | **corregido** | `_port_from_env()` lanza `RuntimeError` nombrando `POSTGRES_PORT` (estilo consistente con `_required`). Prueba: `POSTGRES_PORT=abc`. |
| R3-3 — los tests de stubs exigían entorno/base viva | Sí | **corregido** | El fixture arma la app con `Settings` dummy explícitos y stubbea `fetch_database_version`; los 26 tests corren **sin variables de entorno y sin PostgreSQL** (comando de verificación propio). |
| R3-4 — `ClienteUpdate` sin `tipo` | Sí | **aceptado** | El contrato OpenAPI no incluye `tipo` en la actualización de clientes y el mirror de `schemas.py` es correcto; el TODO del stub es adelanto de 6.7, donde un cambio así exige actualizar el contrato (ver «Requiere coordinación»). |
| R3-001 — seam de renderizado de errores sin prueba de app | Sí | **corregido** | `api/tests/test_error_handlers.py`: ruta de prueba que dispara `P0001 '[RN-99]'` → 409 con `regla: RN-99`; `DatabaseHttpError(404)` → cuerpo `Error` intacto; y en `test_errors_pg.py` el branch genérico de `transaction()` (un `ValueError` se propaga sin convertir y el ROLLBACK se aplica: la fila insertada no persiste). |
| R3-002 — `RuntimeError` genérico enmascaraba defectos | Sí | **corregido** | Excepción centinela `ServerVersionUnavailable` en `repos/salud.py`; el router ya no captura `RuntimeError` a secas: un defecto interno responde **500** y solo la indisponibilidad real responde 503 (pruebas en ambos sentidos). |
| R3-003 — fixtures con claves fijas | Sí | **corregido** | CUIT y nombres de fixture ahora son únicos por corrida (11 dígitos válidos + sufijo uuid); el teardown borra solo sus propias claves. |

Pruebas tras el cierre: **63 passed** con la base efímera (57 previas + 6 de
regresión nuevas) y **26 passed** de stubs con el entorno vacío. TDD: se
observó el RED de cada corrección antes de implementarla (los dos tests de
R3-001 documentan comportamiento ya correcto y funcionan como guardia de
regresión).

## Tarea 6.3 — Capa de repositorios

### Alcance

Módulo `api/app/repos/` con **una función por operación de acceso a datos**,
cada una con su SQL parametrizado y sus transacciones explícitas. Es la capa
que las tareas 6.5–6.10 van a consumir: los routers quedan como estaban
(stubs) y **no contienen SQL ni lógica de persistencia** (verificado por
grep). No se implementó lógica de endpoints ni reglas de negocio de fases
posteriores.

### Arquitectura y convenciones

| Decisión | Criterio |
|---|---|
| Firma | `def f(pool: ConnectionPool, ...) -> ...`; cada función **es dueña de su conexión** (`get_connection` para lecturas, `transaction` para escrituras u operaciones multi-sentencia). Los routers no manejan conexiones. |
| SQL | Exclusivamente parametrizado (`%s` / `%(x)s`), cero interpolación de valores. El `WHERE` dinámico se arma con fragmentos fijos + parámetros bound (con casts explícitos `%(x)s::text` donde PostgreSQL no infiere el tipo). |
| IDs | Siempre `RETURNING`; nunca `nextval`/`currval`. |
| Datos derivados | La API no calcula precios, descuentos, subtotales, totales ni stock: los devuelven los triggers, funciones y vistas. |
| Resultados | `dict_row` (psycopg), tipos nativos de la base; el mapeo a Pydantic es trabajo de los routers (6.5+). |
| Filas de comprobante | Solo `(cod_vino, cantidad)`, insertadas **ordenadas por `cod_vino ASC`** (regla del proyecto y orden de locks de 004). |
| Auditoría de precio | `actualizar_vino` ejecuta `set_config('app.usuario', %s, true)` **como primera sentencia de la transacción** (ámbito transaccional, patrón de `consultas/update.sql` U3); el trigger `fn_tg_vino_precio_auditoria` (SECURITY DEFINER) lo lee solo si cambia `precio_venta`. |

### Inventario de funciones (25 públicas)

| Módulo | Funciones |
|---|---|
| `repos/vinos.py` | `listar_vinos` (filtros + paginación, `COUNT(*) OVER ()` en una sola query), `obtener_vino`, `crear_vino` (vino + composición + maridajes en **una** transacción; RN-05 diferido → 409), `actualizar_vino` (con `set_config`), `eliminar_vino` |
| `repos/clientes.py` | `listar_clientes`, `obtener_cliente` (con subtipo y permisos), `crear_cliente` (cliente + subtipo + permisos en una transacción; nunca envía `id_cliente` ni `descuento`), `actualizar_cliente` (sin cambiar `tipo`), `eliminar_cliente` |
| `repos/comprobantes.py` | `crear_comprobante` (cabecera + renglones en una transacción, patrón I3: los triggers calculan todo), `obtener_comprobante` |
| `repos/transferencias.py` | `crear_transferencia`, `agregar_renglon_transferencia`, `terminar_transferencia`, `procesar_transferencia` (`CALL sp_procesar_transferencia`) |
| `repos/ingresos.py` | ídem con `sp_procesar_ingreso` (`[RN-10]`) |
| `repos/reportes.py` | `top_vinos` (S1), `ventas_por_sala` (S8 sobre `vw_ventas_mensuales_sala`), `vinos_sin_stock` (S6), `transportista_activo` (S7), `trazabilidad_vino` (S9 sobre `vw_ficha_vino`) |

Los reportes **alinearon su semántica con las consultas canónicas de
`consultas/select.sql`** (S1/S6/S7/S8), no con los rótulos del contrato.

### Decisiones y hallazgos

- `obtener_vino` y `trazabilidad_vino` usan `vw_ficha_vino`: una sola query
  devuelve ficha + stock + composición/maridajes como JSONB, que psycopg
  convierte a listas de dicts.
- Los `DELETE` no borran hijos a mano: verificado en 001 que `composicion` y
  `vino_maridaje` son `CASCADE` (y la cascada corre con los privilegios del
  owner). Las FK `RESTRICT` (renglones de comprobante, stock, auditoría) se
  dejan propagar como error mapeado — sin workarounds.
- **Incompatibilidad de comportamiento hallada (documentada, sin improvisar):**
  repetir `terminar` sobre un documento ya `terminado` **no** produce error:
  un `UPDATE` que no cambia el valor de `estado` no dispara la validación de
  transiciones del trigger, así que es un no-op de la base. El único retroceso
  que sí responde es `procesado → terminado` (`[RN-11]`/`[RN-10]` → 409). Los
  tests afirman el comportamiento real de la base, no el imaginado.
- Los permisos se respetan al pie de la letra: las pruebas corren con el pool
  **`app_rw`** y solo los catálogos/stock de fixture se crean como superusuario.
  Hay tests explícitos de frontera (INSERT directo en `bodega` → `42501`;
  UPDATE sobre `renglon_comprobante` → `42501`) que prueban que los repos no
  dependen de privilegios de superusuario.

### Pruebas (TDD, integración contra PostgreSQL 16)

- **RED** observado por ciclo (los módulos aún no existían: `ImportError` en la
  colección) y luego **GREEN**.
- **Suite completa: `109 passed`** = 63 previas + **46 nuevas** de repositorio
  (26 de vinos/clientes + 20 de comprobantes/documentos/reportes).
- Cobertura mínima verificada: happy path por función; filtros y paginación;
  **prueba de parametrización** (`'; DROP TABLE vino; --` como valor → sin
  efecto, tabla intacta); **atomicidad transaccional** (RN-05 diferido → 409 y
  nada persiste; RN-09 sin stock → 409 y nada persiste; duplicado → 409/23505);
  flujo completo crear→renglón→terminar→procesar con efectos reales sobre el
  stock; transiciones inválidas → 409 con `regla` RN-10/RN-11; inexistentes →
  404 (`P0002`); reportes con dataset conocido (orden S1, filtro S6, ganador
  S7, filas S8); fronteras de permiso (`42501`).

### Queda pendiente para 6.5–6.10

- Conectar los routers a estos repos (una operación OpenAPI → una función de
  repo), construir los `PageMeta` en la capa HTTP, mapear dicts a los modelos
  Pydantic y traducir `None` a 404 donde corresponda.
- Filtros/paginación de `GET /vinos` y `GET /clientes` ya soportados por los
  repos; falta exponerlos.
- El `TODO(6.x)` de cada stub marca qué endpoint implementa cada uno.

## Tarea 6.5 — Catálogo de vinos (`GET /vinos`, `GET /vinos/{cod}`)

### Alcance

Primeros endpoints reales de la API: los dos GET del catálogo quedan
conectados a `repos/vinos.py` (`listar_vinos` y `obtener_vino`), con
conversión a los modelos Pydantic del contrato, `PageMeta` correcto y 404 con
el body `Error`. Los `POST`/`PUT`/`DELETE` de `/vinos` siguen siendo stubs con
su `TODO(6.6)`.

### Decisiones

- **Composición de la respuesta**: el router delega todo el acceso a datos en
  el repo (recibe `request.app.state.pool`, patrón de `salud`), convierte las
  filas con `VinoResumen.model_validate` / `VinoDetalle.model_validate` y arma
  `PageMeta(page, per_page, total, total_pages)` con
  `total_pages = (total + per_page - 1) // per_page` (0 cuando `total = 0`).
- **Orden**: el contrato **no define parámetros de ordenamiento** para estas
  operaciones (verificado en `openapi.yaml`); se mantiene el orden
  determinístico del repo (`cod_vino`). No se inventó ningún parámetro.
- **Fidelidad del contrato en los parámetros**: los stubs declaraban `tipo`
  como string libre y `cuit_bodega` sin patrón; ahora `tipo` es el enum y
  `cuit_bodega` valida `^[0-9]{11}$`, como documenta OpenAPI.
- **404**: `DatabaseHttpError(404, {"codigo": "NOT_FOUND", "mensaje": "No
  existe el vino <cod>.", ...})` → el renderizador central emite el body
  `Error` del contrato (sin fugas del formato `{"detail": ...}` de FastAPI).
  Los errores de base siguen fluyendo por los handlers centralizados intactos.

### Pruebas (integración HTTP contra PostgreSQL 16)

`api/tests/test_vinos_endpoints.py` — 13 pruebas con datos controlados
(marcadores únicos por corrida; catálogos vía superusuario, todo lo demás por
los repos como `app_rw`): shape 200 de la página con `meta` exacto; cada filtro
por separado y combinados; paginación con `per_page=2` (páginas disjuntas,
`total` completo, `total_pages` correcto); página fuera de rango → `data: []`;
filtro sin resultados → `total 0`; detalle 200 con `composicion`/`maridajes`/
`stock`; inexistente → 404 con body `Error`. **RED conductual** observado
primero (el stub devolvía el ejemplo hardcodeado sin importar los filtros) y
luego GREEN. **Suite completa: `120 passed`.**

### Ajuste de la matriz de stubs (decisión documentada)

La matriz de 6.2 (`test_stubs.py`) fijaba el comportamiento de stub de las dos
rutas que ahora son reales y quedó en conflicto estructural (esperaba 200 con
payload fijo contra un pool dummy). Se retiraron **solo esas dos filas** con un
comentario: su cobertura real vive en `test_vinos_endpoints.py`. Las filas de
`POST`/`PUT`/`DELETE /vinos` permanecen (siguen siendo stubs). **Regla para
6.6–6.10**: a medida que cada endpoint se vuelva real, se retira su fila de la
matriz y la cobertura pasa a su archivo de pruebas dedicado.

### Incompatibilidad pendiente de decisión (resuelta)

FastAPI respondía **422** `{"detail": [...]}` ante parámetros de query
inválidos mientras el contrato documenta **400** con body `Error`. Quedó
**resuelta** por decisión explícita en la sección «Validación HTTP alineada
con el contrato» de abajo; el comportamiento anterior estuvo pinneado en una
prueba hasta el cambio.

## Validación HTTP alineada con el contrato (post-6.5)

### Objetivo

Los errores de validación de FastAPI (query, path y body) responden **HTTP
400** con el body `Error` del contrato, en lugar del `422 {"detail": ...}`
predeterminado. El **422 del contrato se reserva** para violaciones
semánticas de la base (CHECK `23514`, NOT NULL `23502`), que siguen llegando
desde el mapeo SQLSTATE — sin cambios.

### Implementación

- `api/app/main.py`: un handler global para `RequestValidationError`
  registrado junto a los existentes. Construye un `ErrorBody` reutilizando la
  clase central (`errors.py` intacto) y lo pinta con **el mismo renderizador**
  `_error_response` que usan los otros errores: un solo camino de formato.
- Body resultante: `codigo: "VALIDATION_ERROR"` (código interno, estilo
  `DB_UNAVAILABLE`/`NOT_FOUND`), `mensaje: "La solicitud es inválida."`
  (genérico, nunca un dump del framework), `detalle: "<ubicación>: <mensaje
  genérico de Pydantic>"` (ej. `query.cuit_bodega: String should match
  pattern…`), `regla: null`.
- **Regla de seguridad**: solo se leen `loc` (ubicación) y `msg` (mensaje
  genérico del validador). Nunca se devuelven los valores del input, `ctx`,
  tipos de excepción, trazas, SQL ni detalles internos. La lista se limita a
  5 ítems (`…` si se trunca).
- Uniforme para los tres orígenes: un único `RequestValidationError` cubre
  query, path y body (FastAPI valida antes de ejecutar el handler de la ruta).

### Pruebas

`api/tests/test_validation_errors.py` (7 pruebas): query inválido → 400 con
body `Error` y `query.cuit_bodega` en `detalle`; path inválido (`/vinos/abc`)
→ 400 con `path.cod` (el nombre del parámetro de la ruta); body inválido en
`POST /vinos` (la validación ocurre antes del stub — no se implementó 6.6);
**prueba de no-fuga** (un valor marcador enviado por query no aparece en la
respuesta); paginación fuera de rango (`page=0`) → 400 (mencionado en la
descripción de `BadRequest` del contrato); y uniformidad de `codigo`/`mensaje`
entre los tres orígenes. La prueba de 6.5 que fijaba el 422 pasó a
`test_invalid_query_param_returns_400_with_error_body` (400 + body `Error`).

**Suite completa: `127 passed`** sobre PostgreSQL 16 (001–008, `app_rw`); los
23 tests de SQLSTATE/`DatabaseHttpError` confirman que el manejo central
existente quedó intacto.

## Tarea 6.6 — Alta, modificación y baja de vinos (POST/PUT/DELETE)

### Alcance

Los tres handlers de escritura de `/vinos` dejaron de ser stubs y se conectan
a los repositorios de 6.3. El CRUD de vinos queda completo: GET (6.5) + POST,
PUT y DELETE (6.6). `api/tests/test_stubs.py` perdió las 3 filas de su matriz
(siguiendo el patrón acordado) y la cobertura vive en
`api/tests/test_vinos_endpoints.py`.

### Decisiones

- **POST** → `repo.crear_vino(...)`: 201 con `VinoDetalle`. Todos los errores
  fluyen por el manejo central: RN-05 (composición ≠ 100, diferido al COMMIT)
  → 409 con `regla: RN-05`; clave de negocio duplicada → 409/`23505`; CHECK o
  NOT NULL de la base → 422; padre FK inexistente → 422; validación de
  request → 400. Cero mapeo de errores en el router.
- **PUT** → actualización parcial real: solo se envían al repo los campos que
  el cliente mandó (`body.model_dump(exclude_unset=True)`), con `composicion`
  y `maridajes` como colecciones completas (reemplazo atómico dentro de la
  transacción del repo). Inexistente → 404 con body `Error`.
- **DELETE** → 204 sin cuerpo; inexistente → 404; con movimientos asociados →
  409 vía el handler central (FK `ON DELETE RESTRICT`, la RN-14 del contrato).

### Usuario de la auditoría (hallazgo abierto — decisión pendiente)

Ninguna fuente define de dónde sale el identificador que audita los cambios
de precio: `openapi.yaml` no tiene header ni campo, `docs/contratos.md` solo
documenta el mecanismo (`SET LOCAL app.usuario = ...` con ejemplo
`'admin@bodega.com'`), el enunciado exige el campo `usuario` en la auditoría y
el front está vacío. **No se inventó superficie de contrato**: el router pasa
`usuario=""`, que activa el fallback documentado en la base.

Verificación empírica del fallback (sonda real contra PostgreSQL 16):
`set_config('app.usuario', '', true)` + UPDATE como `app_rw` → la fila en
`auditoria_precio` queda con `usuario = 'app_rw'`. El trigger usa
`session_user` (005:483), que bajo `SECURITY DEFINER` sigue siendo el rol de
conexión — **no** el dueño de la función. Ojo de defensa: `docs/contratos.md:105`
dice que el fallback es `current_user`, pero el SQL usa `session_user`; el
comportamiento real (empírico) es el segundo y el test lo fija (`usuario ==
'app_rw'`).

Queda como decisión abierta (ver «Requiere coordinación»): si la identidad la
manda el cliente (header tipo `X-Usuario` o campo en `VinoUpdate`, ambos
cambios de contrato) o si la auditoría se conforma con el rol de aplicación
hasta que exista autenticación.

### Pruebas (12 nuevas, integración HTTP contra PostgreSQL 16)

Creación con composición de 2 cepas (201, shape `VinoDetalle`); composición
≠ 100 → 409 `P0001`/`RN-05` **y atomicidad** (el vino no queda); duplicado de
clave de negocio → 409/`23505`; CHECK violado → 422 con body `Error` (y la
prueba complementaria de validación de request → 400); PUT de atributos →
200; reemplazo de composición → 200 y el caso atómico (composición inválida →
409 con la composición anterior intacta); **PUT de precio → 200 + fila en
`auditoria_precio`** con `precio_anterior`/`precio_nuevo` y `usuario = 'app_rw'`
(valor empírico fijado en la prueba); PUT inexistente → 404; DELETE → 204 y el
GET posterior → 404; **DELETE con movimientos → 409** (la FK de
`auditoria_precio` es `ON DELETE RESTRICT`, el motor más simple de la RN-14)
con el vino intacto; DELETE inexistente → 404. RED observado primero.
**Suite completa: `136 passed`.**

Nota: `detalle_vino_example` en `routers/vinos.py` **no** es código muerto: lo
importa el stub de reportes (6.10 lo reemplazará junto con los `_EXAMPLE_*`).

### Requiere coordinación

- **P1**: nada bloqueante. D5 funciona sin excepción de RN-12 (evidencia
  arriba); conviene confirmarlo en la defensa y cerrar la nota abierta en
  `consultas/delete.sql`. Si el dataset completo cambia el comportamiento de
  D1/D4/D6 (hoy dan 0), habría que repetir la pasada con seeds.
- **P2**: las pruebas reales de la API necesitan datos mínimos; hoy los
  fixtures se crean como superusuario en las pruebas. Si el seed completo se
  carga en el CI, las pruebas de API podrían correr contra él.
- **P4**: los 25 stubs están listos para integrar (mismos paths/methods/status
  que OpenAPI). Falta sumar a `.env.example` las variables `POSTGRES_HOST` y
  `DB_USER` (propuesta arriba; archivo fuera de mi alcance). El CI no ejecuta
  todavía `pytest api/tests` (habría que instalar `api/requirements.txt` en el
  workflow) — eso es de P4/infra.

### Limitaciones de lo verificado

- La base de verificación es un contenedor efímero con migraciones 001–007 y
  fixtures mínimos: no es el dataset completo de seeds. D1/D4/D6 no tuvieron
  filas que borrar; su corrección sintáctica está probada, su efecto sobre el
  dataset completo no.
- El criterio de `23503` depende de los mensajes estándar en inglés de
  PostgreSQL (fallback documentado para servidores localizados).
- `git`, el informe y las pruebas se ejecutaron en este entorno; no se hizo
  push, PR ni merge por decisión explícita.

## Tarea 6.7 — CRUD de clientes

### Alcance

Las cinco operaciones de `/clientes` dejaron de ser stubs y se conectan a
`repos/clientes.py` (6.3). El CRUD queda completo: listado con filtros y
paginación, detalle, alta con subtipo y permisos, modificación parcial y baja.
`api/tests/test_stubs.py` perdió sus 5 filas de `/clientes` (mismo patrón que
6.5/6.6) y la cobertura vive en `api/tests/test_clientes_endpoints.py`.

### Decisiones

- **GET `/clientes`** → `repo.listar_clientes(...)`: `ClienteResumen` por fila y
  `PageMeta` con `total_pages = (total + per_page - 1) // per_page` (0 cuando
  `total = 0`). `tipo` se valida con el alias `TipoCliente` del contrato
  (`Literal`); un subtipo desconocido responde 400 `VALIDATION_ERROR` por el
  handler central, no 422.
- **GET `/clientes/{id}`** → `repo.obtener_cliente(...)`; `None` → 404 con body
  `Error` (`NOT_FOUND`), igual que el patrón de vinos. El detalle expone los
  campos del subtipo (`zona_cobertura`/`nro_habilitacion` para distribuidor,
  `pais_destino_principal` para exportador) y `permisos` ordenados por
  `cod_permiso`; los campos de otros subtipos quedan en `null`.
- **POST `/clientes`** → `repo.crear_cliente(...)`: 201 con `ClienteDetalle`.
  Nunca se envían `descuento` (GENERATED ALWAYS desde `fn_descuento_cliente`,
  R-002) ni `id_cliente` (identity). La base asigna 10/20/30 % según el tipo y
  lo verifica la prueba. Subtipo y permisos se insertan en la misma transacción
  del repo. Errores por el manejo central: duplicado de documento → 409/`23505`;
  CHECK de la base (p. ej. `ck_permiso_fechas`) → 422/`23514`; FK padre
  inexistente → 422; validación de request → 400.
- **PUT `/clientes/{id}`** → actualización parcial real con
  `body.model_dump(exclude_unset=True)`. `ClienteUpdate` **no** tiene `tipo`:
  cambiarlo queda fuera del contrato (y la FK compuesta de los subtipos lo
  impide en la base). Si viaja `permisos`, el repo reemplaza la colección
  completa dentro de su transacción. Inexistente → 404.
- **DELETE `/clientes/{id}`** → 204 sin cuerpo; inexistente → 404; cliente con
  comprobantes → 409/`23503` por la FK `ON DELETE RESTRICT`, sin rodearla. Los
  subtipos y permisos caen por CASCADE.
- **Serialización de fechas**: el repo devuelve valores nativos (`date`) y los
  esquemas Pydantic del contrato modelan las fechas como `str`. El router las
  normaliza a ISO (`_fecha_iso`) antes de `model_validate`; es adaptación de
  respuesta, no lógica de negocio ni SQL.

### Pruebas (22 nuevas, integración HTTP contra PostgreSQL 16)

Listado con shape exacto y `PageMeta`; filtros `tipo`, `id_localidad` y `q` por
separado y combinados; paginación en páginas disjuntas, página fuera de rango
(`data: []` con meta consistente) y filtro sin coincidencias (`total = 0`,
`total_pages = 0`); detalle de exportador (subtipo + permiso) y de socio (sin
datos de otro subtipo); 404 de detalle; 400 por `tipo` inválido; alta de los tres
tipos (socio 10 %, distribuidor 20 %, exportador 30 %) con roundtrip GET;
`descuento`/`id_cliente` enviados en el POST se ignoran (la base calcula el
descuento); documento duplicado → 409/`23505`; CHECK de permiso invertido →
422/`23514` **y atomicidad** (el cliente no queda); PUT parcial (solo
`direccion`) con `tipo` ignorado y el resto intacto; PUT inexistente → 404;
DELETE → 204 y GET posterior → 404; DELETE inexistente → 404; **DELETE con
comprobante → 409** con el cliente intacto. RED observado primero (21 fallos
contra los stubs). **Suite completa: `153 passed`.**

### Discrepancia detectada (no corregida, fuera de alcance)

`api/openapi.yaml` describe el filtro `q` como «búsqueda parcial por nombre o
documento», pero `repos/clientes.py` solo aplica `c.nombre ILIKE`. Las pruebas
fijan el comportamiento real (nombre); alinear documento requiere tocar el repo
(6.3) y no el contrato. Queda para coordinación con P1/P2 o una corrección
posterior del repo.

### Requiere coordinación

- **P2/P1**: decidir si `q` debe buscar también `nro_documento` (discrepancia
  anterior); hoy el contrato promete más de lo que el repo hace.
- **P4**: las 5 operaciones de `/clientes` ya responden contra la base real; el
  front puede integrarlas con los mismos paths/status de OpenAPI. El resto de
  los stubs (comprobantes, documentos, reportes) sigue pendiente (6.8–6.10).

### Limitaciones de lo verificado

- La base de verificación es el contenedor efímero con migraciones 001–008 y
  fixtures mínimos creados como superusuario en las pruebas; no es el dataset
  completo de seeds.
- La normalización de fechas vive en el router porque los esquemas del
  contrato las declaran `str`; si se migraran a `date`, ese helper se podría
  retirar.
- No se hizo commit, push ni PR por decisión explícita de la tarea.


## Tarea 6.8 — Comprobantes (POST y GET)

### Alcance

Las dos operaciones de `/comprobantes` dejaron de ser stubs y se conectan a
`repos/comprobantes.py` (6.3, ya probado en `test_repos_comprobantes.py`):
`POST /comprobantes` (201 con el detalle completo) y `GET /comprobantes/{nro}`
(200 o 404). `api/tests/test_stubs.py` perdió sus 2 filas de `/comprobantes`
y sus constantes `COMPROBANTE_KEYS`/`COMPROBANTE_CREATE_BODY` (mismo patrón
que 6.5–6.7) y la cobertura HTTP vive en `api/tests/test_comprobantes_endpoints.py`.

### Decisiones

- **POST `/comprobantes`** → `repo.crear_comprobante(...)`: 201 con el
  `Comprobante` completo. El cuerpo lleva SOLO `id_cliente`, `id_sala`
  (opcionalmente `fecha`) y `renglones` como `(cod_vino, cantidad)`: jamás se
  envían `precio_unitario`, `descuento`, `subtotal` ni `total`, ni
  `nro_comprobante` (identity). La base calcula todo por
  triggers (T1 completa precio/descuento/subtotal y valida stock con RN-09;
  T2 descuenta `stock_sala` y recalcula la cabecera con RN-08) y el repo
  inserta los renglones ordenados por `cod_vino ASC` (orden único de locks).
- **GET `/comprobantes/{nro}`** → `repo.obtener_comprobante(...)`; `None` →
  404 con body `Error` (`NOT_FOUND`, mensaje `No existe el comprobante <nro>.`),
  igual que el patrón de clientes/vinos. La respuesta expone la cabecera con
  los totales calculados por la base y los renglones con sus datos derivados,
  en el orden en que la base los guarda (`cod_vino ASC`).
- **Errores 100 % centralizados**: el router no mapea nada. Stock insuficiente
  → `P0001 '[RN-09] …'` → 409 con `regla: RN-09` y **cero persistencia**
  (ROLLBACK verificado por la prueba); `cod_vino` repetido dentro de
  `renglones` → PK compuesta 23505 → 409; `id_cliente` inexistente → FK de la
  cabecera 23503 → 422; cuerpo inválido (campo ausente) → 400
  `VALIDATION_ERROR` por el handler del framework.
- **Serialización de fechas**: mismo helper `_fecha_iso` que clientes — el repo
  devuelve `date` nativo y el esquema del contrato lo declara `str`.
- **Discrepancia de la FK de vino**: un `cod_vino` inexistente NO produce
  422/23503 como un `id_cliente` inexistente: el trigger T1 de
  `renglon_comprobante` valida el stock del vino y lanza `[RN-09]` (409)
  ANTES de que la FK contra `vino` pueda fallar. La prueba
  `test_crear_comprobante_vino_inexistente_409_rn09_a_nivel_base` fija ese
  comportamiento real de la base: la API no lo altera (regla de oro).

### Pruebas (8 nuevas, integración HTTP contra PostgreSQL 16)

POST 201 con 2 renglones enviados en orden inverso y totales exactos
verificados con fuente independiente (precio 100.00, socio 10 % de R-002:
renglones 270/180, cabecera subtotal 500 / descuento 50 / total 450) más
renglones presentados ordenados por `cod_vino ASC` y stock descontado por la
base (5→2 y 3→1); roundtrip GET 200 idéntico al POST; GET inexistente → 404
`Error`; stock insuficiente → 409 `RN-09` con **atomicidad** (0 comprobantes
del cliente, stock intacto) y duplicado de `cod_vino` → 409/`23505` igualmente
atómico; `id_cliente` inexistente → 422/`23503`; `cod_vino` inexistente →
409 `[RN-09]` (T1 decide antes que la FK); cuerpo inválido (falta `id_sala` /
falta `renglones`) → 400 `VALIDATION_ERROR`. RED observado primero: **6
fallos contra los stubs** (el test de 400 pasa en RED porque la validación
del framework corre antes del handler stub). **Suite completa: `159
passed`** (153 base + 8 nuevos − 2 filas de stub retiradas).

### Discrepancias detectadas (no corregidas, fuera de alcance)

- **Corregido post-6.8:** `api/app/schemas.py` `ComprobanteCreate.renglones`
  no replicaba el `minItems: 1` del contrato, ni
  `ComprobanteRenglonCreate.cantidad` el `minimum: 1` (un `renglones: []` se
  aceptaba y una `cantidad: 0` llegaba a la base y respondía 422/`23514` en
  vez del 400 del contrato). Fidelidad restaurada en `schemas.py`
  (`Field(min_length=1)` / `Field(ge=1)`) con dos casos nuevos en la prueba
  de cuerpo inválido (400 `VALIDATION_ERROR` para ambos).
- El POST ya documenta los status 400/409/422 del manejo central, así que no
  hace falta tocarlo; una próxima revisión del contrato podría agregar una
  nota para el caso particular de `cod_vino` inexistente (responde 409 con
  `regla: RN-09`, dentro del 409 genérico de Conflict ya previsto).

### Requiere coordinación / Limitaciones

- **P4**: `/comprobantes` ya responde contra la base real con los paths y
  status de OpenAPI; el resto de los stubs (transferencias, ingresos,
  reportes) sigue pendiente (6.9–6.10).
- La base de verificación sigue siendo el contenedor efímero con migraciones
  001–008 y catálogos mínimos creados como superusuario en las pruebas.
- No se hizo commit, push ni PR por decisión explícita de la tarea.

## Tarea 6.9 — Transferencias e ingresos

### Alcance

Las ocho operaciones de documentos dejaron de ser stubs y se conectan a
`repos/transferencias.py` e `repos/ingresos.py` (6.3, ya probados en
`test_repos_documentos.py`): para cada circuito, `POST` de cabecera,
`POST …/renglones`, `POST …/terminar` y `POST …/procesar`.
`api/tests/test_stubs.py` perdió sus 8 filas (4 de `/transferencias` y 4 de
`/ingresos`) y sus constantes `TRANSFERENCIA_KEYS`/`INGRESO_KEYS`/
`TRANSFERENCIA_CREATE_BODY`/`INGRESO_CREATE_BODY`/`REGLON_CREATE_BODY` (mismo
patrón que 6.5–6.8) y la cobertura HTTP vive en
`api/tests/test_documentos_endpoints.py`. Solo `/salud` y `/reportes`
(6.10) siguen en la matriz de stubs.

### Decisiones

- **`POST /transferencias`** → `repo.crear_transferencia(...)`: 201 con la
  cabecera en `en_confeccion`. El cuerpo lleva SOLO `id_sala`:
  `fecha_confeccion` NUNCA viaja (el trigger T5 fuerza `CURRENT_DATE`,
  RN-11) y `estado` toma el DEFAULT. La prueba envía además una
  `fecha_confeccion` intrusa y verifica que el 201 devuelve hoy: Pydantic
  descarta el campo extra y la base fuerza la fecha.
- **`POST …/renglones`** → solo `(cod_vino, cantidad)` y solo en
  `en_confeccion`: editar renglones fuera de ese estado dispara T6
  (`[RN-12]`, P0001 → 409) sin dejar nada escrito. Documento inexistente →
  404 con body `Error` (`NOT_FOUND`, mensaje `No existe la transferencia
  <nro>.` / `No existe el ingreso <cod>.`), mismo patrón de clientes/vinos.
- **`POST …/terminar`** → `UPDATE` de estado validado por el trigger (T4/T3,
  RN-11/RN-10): transición inválida → 409 con `regla`. **Decisión abierta
  (P1/P3)**: repetir `terminar` sobre un documento ya `terminado` es un
  no-op que responde 200 — el trigger compara OLD vs NEW y no se dispara si
  `estado` no cambia. Se cableó así, sin inventar un 409; el contrato no
  distingue el caso y el equipo debe decidir si se documenta la idempotencia
  o se agrega el 409.
- **`POST …/procesar`** → `CALL sp_procesar_transferencia` /
  `CALL sp_procesar_ingreso` dentro de la transacción del repo. Errores 100 %
  centralizados: documento inexistente → P0002 → 404; precondición violada
  (`[RN-11]`/`[RN-10]`, incluido stock insuficiente en el depósito) → P0001 →
  409 con `regla` y **cero persistencia** (la llamada entera hace
  ROLLBACK). La API no calcula ni mueve una botella.
- **`POST /ingresos`** → misma forma que transferencias con `cod_ingreso` y
  `fecha` opcional: si no viaja, el `COALESCE(%s, CURRENT_DATE)` del INSERT
  usa la fecha del día (RN-10).
- **Dos 404 de origen distinto**: en `/renglones` y `/terminar` el repo
  devuelve `None` y el router levanta `NOT_FOUND`; en `/procesar` el que
  habla primero es el procedimiento (P0002 → 404, `codigo: P0002`). Mismo
  status, `codigo` distinto según quién detecte la ausencia.
- **Serialización de fechas**: mismo helper `_fecha_iso` que 6.7/6.8 — el
  repo devuelve `date` nativo y los esquemas del contrato lo declaran `str`.

### Pruebas (18 nuevas, integración HTTP contra PostgreSQL 16)

Por circuito: alta 201 con shape completo (`renglones: []` incluidos) y fecha
forzada/por defecto del día; renglón 201 en `en_confeccion`; renglón tras
`terminar` → 409 `RN-12` con atomicidad (conteo de renglones intacto);
`terminar` 200 con estado visible y repetición 200 (no-op, decisión abierta);
`procesar` antes de `terminar` → 409 `RN-11`/`RN-10` con stock intacto;
`procesar` 200 con efectos reales (transferencia: depósito 10→7 y sala 0→3;
ingreso: `stock_deposito` upserteado en 3 y 120) y stock insuficiente → 409
`RN-11` atómico (depósito, sala y estado sin cambios); `terminar` tras
`procesado` → 409; las tres acciones sobre documento inexistente → 404
(`NOT_FOUND` en renglones/terminar, `P0002` en procesar); cuerpo inválido →
400 `VALIDATION_ERROR`. RED observado primero: **15 fallos, 3 aprobadas**
contra los stubs (las 3 que pasaban: los dos 400 —la validación del framework
corre antes del handler stub— y el 200 de `terminar`, idéntico al payload
fijo del stub). GREEN: **18 aprobadas**. **Suite completa: `169 passed`**
(159 base + 18 nuevas − 8 filas de stub retiradas). Redocly: válida, solo las
2 advertencias conocidas.

### Discrepancias detectadas (corregidas post-6.9)

- **Corregido:** `api/app/schemas.py` `RenglonDocumentoCreate.cantidad` no
  replicaba el `minimum: 1` del contrato (mismo tipo de fidelidad que se
  corrigió en 6.8 para `ComprobanteRenglonCreate`): una `cantidad: 0` pasaba
  la validación del framework y llegaba a la base. Fidelidad restaurada con
  `Field(ge=1)` y caso nuevo en la prueba de cuerpo inválido (400).
- **Corregido:** `api/app/schemas.py` `IngresoCreate.cuit_bodega` no
  replicaba el `pattern: '^[0-9]{11}$'` del contrato. Fidelidad restaurada
  con `Field(pattern=...)` y caso nuevo en la prueba de cuerpo inválido (400).

### Requiere coordinación / Limitaciones

- **P1/P3**: cerrar la decisión abierta «repetir `terminar` → 200 idempotente
  vs 409» y documentarla en el contrato si se elige la primera opción.
- **P4**: los 8 endpoints de documentos ya responden contra la base real con
  los paths y status de OpenAPI; solo quedan los stubs de `/reportes` (6.10).
- La base de verificación sigue siendo el contenedor efímero con migraciones
  001–008 y catálogos mínimos creados como superusuario en las pruebas.
- No se hizo commit, push ni PR por decisión explícita de la tarea.

## Tarea 6.10 — Reportes

### Alcance

Las cinco operaciones de solo lectura de `/reportes` dejaron de ser stubs y se
conectan a `repos/reportes.py` (6.3, ya probado en
`test_repos_reportes.py`): `GET /reportes/top-vinos` (S1), `GET
/reportes/ventas-por-sala` (S8, vista `vw_ventas_mensuales_sala`), `GET
/reportes/vinos-sin-stock` (S6), `GET /reportes/transportista-activo` (S7) y
`GET /reportes/trazabilidad/{cod}` (S9, vista `vw_ficha_vino`).
`api/tests/test_stubs.py` perdió sus 5 filas de `/reportes` y sus constantes
`TOP_VINO_KEYS`/`VENTA_MENSUAL_KEYS`/`VINO_SIN_STOCK_KEYS`/
`TRANSPORTISTA_KEYS`/`VINO_DETALLE_KEYS`/`_PDF` (mismo patrón que 6.5–6.9) y
la cobertura HTTP vive en `api/tests/test_reportes_endpoints.py`: la matriz de
stubs quedó solo con `/salud`. Además se eliminó el código de ejemplo
heredado de 6.5: `detalle_vino_example` y las constantes `_EXAMPLE_*` en
`routers/vinos.py` ya no tienen ningún usador (el único era el stub de
reportes, que este 6.10 reemplaza); se verificó antes por grep que nada más
importaba esos nombres y se borró el import correspondiente del router de
reportes.

### Decisiones

- **Solo lectura end-to-end**: los 5 GET delegan en el repositorio
  (`repo_reportes.*`) y solo convierten las filas a Pydantic; la API no
  calcula ningún total, stock ni ranking (regla de oro). No hay SQL ni
  mapeo de errores en el router.
- **Parámetros espejo del contrato**: `limite` con `Query(ge=1, le=100)`
  (mínimo/máximo del contrato en 6.5–6.9); `id_sala` requerido;
  `desde`/`hasta` tipados como `date` nativo — una fecha malformada
  responde 400 `VALIDATION_ERROR` en el límite HTTP y nunca llega a la
  base (evita caer en un SQLSTATE `22007`, que el mapa central no cubre
  con 400).
- **Serialización**: `mes` llega como `date` nativo de
  `vw_ventas_mensuales_sala` y el contrato lo declara `str` (fecha ISO,
  primer día del mes) — mismo helper `_fecha_iso` que 6.7–6.9.
  `monto_total` (`numeric`) lo coerciona Pydantic al `float` del esquema.
- **Dos 404 en el patrón usado hasta acá**: `transportista-activo` → 404
  cuando ningún transportista tuvo ingresos en el último mes (el repo
  devuelve `None` con `LIMIT 1` y `COUNT`); `trazabilidad/{cod}` → 404
  `No existe el vino <cod>.`, idéntico a `GET /vinos/{cod}` (ambos leen la
  misma ficha vía `_cargar_ficha` sobre `vw_ficha_vino`).
- **Lista vacía = 200 `[]`**: si ningún vino cumple la condición del
  reporte (o el filtro mensual excluye todo el rango), se responde 200 con
  el arreglo vacío; no se inventa un 404 que el repositorio no decide.

### Pruebas (10 nuevas, integración HTTP contra PostgreSQL 16)

Mismo dataset tipo `test_repos_reportes.py` con marcadores únicos: 2 vinos
vendidos (A 2 botellas × 100.00, B × 50.00; socio −10 % de R-002), C sin
stock con 7 en depósito, transportista activo con 2 ingresos de hoy y viejo
con 1 de hace 35 días. Verificaciones: top-vinos ordenado `SUM(cantidad)
DESC` con valores exactos (A: 2, B: 1) y corte `limite=1`;
`limite` 0 y 101 → 400 `VALIDATION_ERROR`; ventas-por-sala con la fila
exacta de la vista (3 botellas, 225.00 = 180 + 45) más filtro
`desde`/`hasta` inclusive y `desde` futuro → 200 `[]` (reporte vacío);
fecha malformada `desde=ayer` → 400; vinos-sin-stock con única fila exacta
(0/7) idéntica en una segunda sala sin ninguna fila de stock (COALESCE) y
`id_sala` ausente → 400; transportista-activo con el más cargado (2
ingresos) y sin ingresos → 404 (dataset recreado en el `finally` de la
misma prueba); trazabilidad 200 con la ficha **idéntica a la de `GET
/vinos/{cod}`** (composición 100 %, stock 0/8/8 tras la venta) y vino
inexistente → 404 `Error` `NOT_FOUND`. RED observado primero: **9 fallos,
1 aprobada** contra los stubs (la que pasa: `id_sala` requerida —la
validación del framework corre antes del handler stub—). GREEN: **10
aprobadas**. **Suite completa: `174 passed`** (169 base + 10 nuevas − 5
filas de stub retiradas). Redocly: válida, solo las 2 advertencias
conocidas.

### Requiere coordinación

- **P2 — rótulos de consultas S**: el contrato openapi etiqueta S1
  top-vinos, S8 ventas-por-sala, S6 vinos-sin-stock, S7
  transportista-activo y S9 trazabilidad, mientras que la semántica
  canónica que implementa el repositorio viene de `consultas/select.sql`:
  el ranking de vinos es S4 allí (no S1), stocks/vinos-sin-stock es S6,
  transportistas S7/I1 y ventas S8; la trazabilidad no existe como consulta
  «S» en select.sql (ficha de `vw_ficha_vino`). El repositorio fijó las
  SEMÁNTICAS del select.sql aunque los rótulos difieran: P2 debe unificar
  los números en una fuente única (contrato o select.sql).
- **P2/P3 — 404 de `/reportes/vinos-sin-stock`**: el contrato documenta un
  404 (`NotFound`) para esa operación, pero el repositorio no distingue
  «sala inexistente» de «sala sin vinos con esa condición» (ambas → 200
  con lista vacía) y ninguna otra fuente define qué dispara el 404. No se
  inventó una consulta extra de existencia de sala en el router (regla de
  oro): decidir con P2 si se quita el 404 del contrato o si el caso pasa a
  la capa de datos.
- **P1/P2 — `22007` fuera del mapa central**: `map_db_error` no cubre
  `22007` (formato de fecha/hora inválido) con 400; hoy no alcanza a ser
  observado por HTTP porque `desde`/`hasta` se validan como `date` en el
  router. Si otra entrada futura puede provocar un `22007` dentro de la
  base, correspondería mapearlo a 400 en `errors.py` (Responsable: P3).
- **P4**: los 5 endpoints de reportes responden contra la base real con
  los paths, parámetros y status de OpenAPI; la matriz de stubs queda solo
  con `/salud` (6.11+ ya no tiene operaciones HTTP restantes en el
  contrato).

### Limitaciones de lo verificado

- La base de verificación sigue siendo el contenedor efímero con migraciones
  001–008 y catálogos mínimos creados como superusuario en las pruebas; los
  criterios de desempate del ranking (`cod_vino ASC`) y el corte por
  `LIMIT` ya quedaron fijados a nivel repositorio en
  `test_repos_reportes.py`.
- No se hizo commit, push ni PR por decisión explícita de la tarea.

## Tarea 6.12 — Demostración de inyección SQL fallida

### Alcance

Demostrar en vivo que un valor malicioso enviado como **valor de filtro**
nunca se interpreta como SQL: viaja como parámetro bound y se compara como
texto literal. La prueba automatizada equivalente ya existe
(`test_filtros_seguros_contra_inyeccion` en `test_repos_vinos.py` y
`test_repos_clientes.py`); esta sección deja la **captura** pedida por el
plan (6.12).

### Captura (API viva sobre PostgreSQL 16 efímero, sesión 2026-11-09)

```console
$ curl -s "http://127.0.0.1:8099/vinos?nombre=%27%3B%20DROP%20TABLE%20vino%3B%20--"
{"data":[],"meta":{"page":1,"per_page":20,"total":0,"total_pages":0}}

$ curl -s "http://127.0.0.1:8099/clientes?q=%27%3B%20DELETE%20FROM%20cliente%3B%20--"
{"data":[],"meta":{"page":1,"per_page":20,"total":0,"total_pages":0}}

$ psql -tAc "SELECT 'vino existe, filas=' || count(*) FROM vino;
              SELECT 'cliente existe, filas=' || count(*) FROM cliente;"
vino existe, filas=0
cliente existe, filas=0
```

Los dos valores decodificados son `'; DROP TABLE vino; --` y
`'; DELETE FROM cliente; --`. La API responde 200 con resultado vacío (el
texto literal no coincide con ningún nombre) y **ambas tablas siguen
existentes** después de los intentos. No hay concatenación de valores del
usuario en ninguna consulta: todos los filtros viajan como parámetros bound
(`%(x)s`) con casts explícitos, y los comodines `%%` del `ILIKE` viven en el
literal SQL, no en el input.

## Tarea 6.13 — Dockerfile de la API y coherencia OpenAPI/rutas

### Alcance

Dos verificaciones pedidas por el plan (6.13): (a) un `Dockerfile` para la
API que `docker compose` pueda referenciar desde el lado de P4, y (b) la
coherencia entre `api/openapi.yaml` y las rutas reales.

### Dockerfile (`api/Dockerfile`)

- Imagen `python:3.11-slim`; instala `api/requirements.txt` (pinneado) y
  copia solo `api/app`. Contexto de build = raíz del repo:
  `docker build -f api/Dockerfile -t bodegas-api .`
- **Sin secretos en la imagen**: sin `ENV` de credenciales (el linter
  `SecretsUsedInArgOrEnv` lo marca incluso con valores vacíos); las
  variables viajan en `docker run --env-file .env`. La app falla rápido si
  falta configuración (`app/config.py`).
- `HEALTHCHECK` contra `GET /salud` (503 si la base no está → unhealthy).
- **Verificado**: `docker build` completo, exit 0, sin warnings. El
  `docker compose up` conjunto (base + API) queda del lado de P4 (el compose
  es su archivo); receta de ejecución documentada en el propio Dockerfile.

### Coherencia OpenAPI ↔ rutas reales

Cotejo automático (script que compara `api/openapi.yaml` con `app.openapi()`
de la app armada con los 7 routers):

```
operaciones contrato: 26 | rutas app: 26
en contrato sin ruta: []
rutas sin contrato: []
COHERENCIA: OK — las 26 operaciones del contrato tienen ruta real
```

Con 6.10 terminaron los stubs: las 26 operaciones (25 del contrato + `/salud`)
apuntan a implementación real contra la base. La matriz `test_stubs.py` quedó
reducida a `/salud` y la cobertura de cada ruta vive en sus pruebas HTTP.

### Estado de 6.11 (pruebas automáticas)

El mínimo del plan (≥8 pruebas, ≥3 que violen reglas) está superado: la
suite tiene 174 pruebas con múltiples violaciones de reglas verificadas
(RN-05 diferido, RN-09 sin stock, 23505 duplicados, 23503 FK, 422 CHECK,
42501 privilegios, 400 validación). Lo que falta de 6.11 es la integración
al CI (correr `pytest api/tests` en el workflow), que es del alcance de P4.

### Requiere coordinación

- **P4**: referenciar `api/Dockerfile` en `docker-compose.yml` y agregar la
  instalación de `api/requirements.txt` + `pytest api/tests` al workflow de
  CI (6.11).
