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
