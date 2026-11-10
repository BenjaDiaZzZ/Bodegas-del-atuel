# Informe de continuidad — P3 API · Sesión del 2026-11-09

Documento autosuficiente para retomar el trabajo en una sesión nueva de
OpenCode. Todo lo que dice aquí está respaldado por código, pruebas ejecutadas
o documentación citada. Última tarea completada en la sesión: **6.6 (CRUD de
vinos)**. Próxima tarea: **6.7 (CRUD de clientes)**.

---

## 1. Estado de Git

- **Rama:** `feature/p3-api-fase6` · **HEAD:** `5998f53`
  (`Merge remote-tracking branch 'origin/main' into feature/p3-api-fase6`).
- **Commits de la rama** (sobre `origin/main` = `65a84cf` ya integrado vía merge):
  | Commit | Contenido |
  |---|---|
  | `5d68a96` | fix(api): OpenAPI alineado con los CHECK de 002 (tarea A) |
  | `6ee1b4e` | feat(api): esqueleto FastAPI + `/salud` real (6.1) |
  | `ead7fa3` | feat(api): stubs de las 25 operaciones (6.2) |
  | `d876a6f` | test(api): aserciones de forma de respuesta (advisories R3-1/R3-2) |
  | `2d1e112` | feat(api): mapeo central SQLSTATE→HTTP (6.4) |
  | `7db0303` | fix(consultas): D3 con `fn_antiguedad_anios` (5.3) + evidencia D5 |
  | `4005040` | fix(api): cierre de advisories de revisión con tests de regresión |
  | `5998f53` | merge de `origin/main` (17 commits del equipo, sin conflictos) |
- **Cambios SIN COMMIT en el worktree** (todo de 6.3 + corrección 400 + 6.5 + 6.6; los últimos días se trabajó sin commits por instrucción explícita):
  - Modificados: `api/app/main.py`, `api/app/repos/__init__.py`, `api/app/routers/vinos.py`, `api/tests/test_stubs.py`, `docs/informe/07-api.md`.
  - Nuevos sin trackear: `api/app/repos/{vinos,clientes,comprobantes,transferencias,ingresos,reportes}.py`, `api/tests/test_repos_{vinos,clientes,comprobantes,documentos,reportes}.py`, `api/tests/test_validation_errors.py`, `api/tests/test_vinos_endpoints.py`, más este archivo.
  - **Sugerencia de commits para la próxima sesión** (work units): (1) `feat(api): repository layer (6.3)` — repos + test_repos_*; (2) `feat(api): wine catalog endpoints (6.5)` — routers/vinos GET + test_vinos_endpoints + ajuste de test_stubs; (3) `fix(api): validation errors respond 400 with Error body` — main.py + test_validation_errors; (4) `feat(api): wine write endpoints (6.6)` — POST/PUT/DELETE + tests; (5) docs.
- Sin push, sin PR, sin merges adicionales. `git diff --check`: limpio.
- Existen también archivos de tooling sin trackear que NO son del proyecto: `.agents/`, `.atl/`, `AGENTS.md`, `skills-lock.json` — no commitearlos.
- Nota RDD: receipt-driven development está activo globalmente; al commitear, correr `gentle-ai review assess --cwd . --agent opencode --base-ref <frontera> --committed-only --json` y seguir `next_transition`.

### Actualización (cierre de la sesión 2026-11-09, fase de commits)

La sugerencia de la tabla anterior se ejecutó como commits de work-unit
(todos verificados con la suite sobre PostgreSQL 16 efímero, árbol por
commit):

| Commit | Contenido |
|---|---|
| `8766704` | `feat(api): add repository layer for vinos (6.3)` |
| `99f4759` | `feat(api): add repository layer for clientes (6.3)` |
| `f7a4d47` | `feat(api): add repository layer for comprobantes (6.3)` |
| `fe91130` | `feat(api): add repository layer for transferencias and ingresos (6.3)` |
| `f229773` | `feat(api): add repository layer for reportes (6.3)` |
| `9c076c8` | `feat(api): add vinos catalog endpoints with pagination (6.5)` |
| `e5708ae` | `fix(api): respond 400 with contract Error body on validation errors` |
| `8d7ae6b` | `feat(api): add vinos write endpoints with price audit (6.6)` |
| `ad3bde9` | `feat(api): add clientes CRUD endpoints (6.7)` |
| (docs) | informe 6.3-6.7 + continuidad + `odd/tasks/6-7-crud-clientes.md` |

Nota RDD: las revisiones de los slices `8766704` y `99f4759` fueron
aprobadas y sus autoridades quemadas; `f7a4d47` y `fe91130` fueron salteadas
por decisión del usuario; durante el slice de `f229773` el usuario
desactivó RDD a nivel clone (`gentle-ai review mode disable --scope clone`),
por lo que el resto avanza bajo política ordinaria (gates:
`disabled/unmanaged`). Sin push ni PR.

## 2. Estado de las fases del plan P3

| Tarea | Estado | Evidencia |
|---|---|---|
| 0.4/0.5 Stack y consultas al docente | completada (previa) | `docs/tablero.md`, guía |
| 1.7 OpenAPI borrador + revisión | completada | PR #2 + tarea A de esta rama (`5d68a96`) |
| 2.5 Vistas y roles | completada | `006_vistas.sql`/`007_roles.sql` + tests (PRs #13/#15/#22, en main) |
| 5.3 `consultas/delete.sql` D1–D6 | completada | `7db0303`; D5 probado en PG16 real (borra 1 fila; RN-12 no bloquea la cascada) |
| 6.1 Esqueleto y `/salud` | completada | `6ee1b4e` |
| 6.2 Stubs | completada | `ead7fa3` (25 operaciones) |
| 6.3 Capa de repositorios | completada | worktree (25 funciones, tests de integración) |
| 6.4 Errores SQLSTATE | completada | `2d1e112` (mapeo total + COMMIT en el try) |
| 6.5 Catálogo de vinos (GET) | completada | worktree (filtros, paginación, 404) |
| 6.6 Alta/mod/baja de vinos | completada | worktree (POST/PUT/DELETE + auditoría de precio) |
| 6.7 CRUD de clientes | **pendiente** | repos de clientes ya implementados y probados (6.3); falta cablear los routers |
| 6.8 Comprobantes | pendiente | repo `crear_comprobante`/`obtener_comprobante` listo |
| 6.9 Transferencias e ingresos | pendiente | repos listos (crear/renglón/terminar/procesar) |
| 6.10 Reportes | pendiente | repo `reportes.py` listo (S1/S6/S7/S8/S9) |
| 6.11 Pruebas automáticas | parcial | 136 tests (>8 y >3 violando reglas); falta que las corra el CI |
| 6.12 Demo de inyección SQL | pendiente | la prueba de parametrización existe; falta la demo/captura para el informe |
| 6.13 Dockerfile + coherencia | pendiente | — |
| 6.14 Revisión de seguridad/lógica | pendiente (P1) | — |
| 8.5 Despliegue de la API | pendiente (P4 + P3) | — |
| 9.2 Informe final | parcial | `docs/informe/07-api.md` completo hasta 6.6; falta consolidación final |

## 3. Arquitectura actual de la API

```
HTTP → routers (app/routers/*.py)  →  repos (app/repos/*.py)  →  PostgreSQL
        · FastAPI + modelos Pydantic     · una función por operación       · SQL parametrizado
        · sin SQL ni persistencia        · cada función es dueña de su     · triggers/funciones/vistas
        · traducen None→404 y arman        conexión (get_connection /       calculan lo derivado
          PageMeta                         transaction con COMMIT en el
        · errores → handlers centrales       try y ROLLBACK)
```

- **`app/main.py`**: `create_app()` (settings se resuelven en el lifespan), registra 3 handlers globales: `PsycopgError` → mapeo SQLSTATE, `DatabaseHttpError` → body ya mapeado, `RequestValidationError` → **400** con body `Error`. Todos renderizan por `_error_response`.
- **`app/errors.py`**: único punto de conversión PostgreSQL→HTTP (`map_db_error`) + `ErrorBody` (shape del contrato: `codigo`, `mensaje`, `detalle`, `regla`).
- **`app/db.py`**: `ConnectionPool` (psycopg 3 + psycopg_pool), `get_connection(pool)` y `transaction(pool)` con `BEGIN…COMMIT` dentro del `try` (obligatorio por RN-05 diferido).
- **`app/config.py`**: settings solo desde variables de entorno (`POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `DB_USER` default `app_rw`, `DB_PASSWORD`).
- **`app/schemas.py`**: modelos Pydantic que espejan `api/openapi.yaml`.
- **`app/repos/`**: `salud`, `vinos`, `clientes`, `comprobantes`, `transferencias`, `ingresos`, `reportes` (25 funciones públicas).
- **Regla de oro**: la API nunca calcula precios, descuentos, subtotales, totales ni stock; nunca envía `cliente.descuento` ni PKs identity; IDs por `RETURNING`; renglones solo `(cod_vino, cantidad)` ordenados por `cod_vino ASC`.

## 4. Endpoints

- **Implementados (6):** `GET /salud`, `GET /vinos`, `GET /vinos/{cod}`, `POST /vinos`, `PUT /vinos/{cod}`, `DELETE /vinos/{cod}`.
- **Stubs pendientes (20):** `/clientes` (5), `/comprobantes` (2), `/transferencias` (4), `/ingresos` (4), `/reportes` (5) — cada uno con su `TODO(6.x)` y sus repos ya implementados. Al volverse real cada endpoint: quitar su fila de `api/tests/test_stubs.py` y cubrirlo con pruebas HTTP dedicadas (patrón ya aplicado con `/vinos`).

## 5. Decisiones técnicas y reglas importantes

1. **Mapeo SQLSTATE→HTTP** (6.4): `23505`→409; `23503`→409 (bloqueado por dependientes) o 422 (padre inexistente) según el `detail` de PostgreSQL, fallback 422; `23514`/`23502`→422; `P0001`→409 conservando `[RN-xx]` en `mensaje` y `regla`; `P0002`→404; `22P02`→400; `40001`/`40P01`→503 reintentable; `42501` y desconocidos→500 sin fugas.
2. **Validación de request → 400** con body `Error` (`codigo: VALIDATION_ERROR`), solo con `loc` + `msg` genérico (nunca valores del input). El 422 del contrato queda para violaciones semánticas de la base.
3. **COMMIT dentro del try** en `transaction()`: RN-05 (`tg_composicion_cien`) es `DEFERRABLE INITIALLY DEFERRED` y falla al COMMIT (probado con test real).
4. **Auditoría de precio**: `set_config('app.usuario', %s, true)` como primera sentencia de la transacción del UPDATE (ámbito transaccional; el pool reutiliza conexiones).
5. **PUT parcial**: `body.model_dump(exclude_unset=True)` — solo viajan los campos que el cliente mandó.
6. **404 de negocio**: repo devuelve `None` → `DatabaseHttpError(404, {codigo: "NOT_FOUND", mensaje: "No existe el <recurso> X."})` → renderizado central.
7. **`PageMeta`**: `total_pages = (total + per_page - 1) // per_page` (0 si total=0); `total` vía `COUNT(*) OVER ()` en la misma query.
8. **Orden de renglones**: `cod_vino ASC` (regla del proyecto + orden de locks de 004). Sin `nextval`/`currval`.
9. **Sin identidad para la auditoría** (hallazgo abierto, ver §7).

## 6. Pruebas: resultados y cómo reproducirlos

**Resultado final observado: `136 passed`** sobre PostgreSQL 16 con migraciones 001–008 y pool `app_rw`. Desglose: 6 del esqueleto, 24 de la matriz de stubs, 20 del mapeo de errores sin base, 4 reales de errores (RN-05, P0001, 23505, P0002), 1 de regresión de `/salud`, 7 de validación (400), 25 de endpoints de vinos (GET+CRUD), 46 de repositorios, 3 de handlers de error, y el resto de configuración/db.

Reproducir desde cero:

```bash
# 1. Base efímera PostgreSQL 16 (nunca la base real ni .env)
docker run -d --name bodegas-p3-pg16 -e POSTGRES_PASSWORD=<pw> \
  -e POSTGRES_DB=bodegas_del_atuel -p 127.0.0.1:<puerto>:5432 postgres:16
for f in db/migrations/00*.sql; do
  PGPASSWORD=<pw> psql -h 127.0.0.1 -p <puerto> -U postgres -d bodegas_del_atuel \
    -v ON_ERROR_STOP=1 -q -f "$f"
done
PGPASSWORD=<pw> psql -h 127.0.0.1 -p <puerto> -U postgres -d bodegas_del_atuel \
  -c "ALTER ROLE app_rw WITH LOGIN PASSWORD '<pw_app_rw>';"

# 2. Entorno Python (venv aislado; dependencias en api/requirements.txt)
uv venv /tmp/opencode/venv-bodegas
uv pip install --python /tmp/opencode/venv-bodegas/bin/python \
  fastapi "uvicorn[standard]" "psycopg[binary]" psycopg-pool pytest httpx

# 3. Suite completa
POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=<puerto> POSTGRES_DB=bodegas_del_atuel \
DB_USER=app_rw DB_PASSWORD=<pw_app_rw> PGSU=postgres PGSUPW=<pw> \
  /tmp/opencode/venv-bodegas/bin/python -m pytest api/tests -q

# 4. Contrato
npx @redocly/cli lint api/openapi.yaml        # exit 0, 2 warnings preexistentes

# 5. Tests de base (como superusuario) y de concurrencia
psql ... -v ON_ERROR_STOP=1 -f db/tests/db_tests.sql
psql ... -f db/tests/test_006_vistas.sql && psql ... -f db/tests/test_007_roles.sql
PGHOST=... PGPORT=... PGUSER=postgres PGDATABASE=bodegas_del_atuel PGPASSWORD=<pw> \
  bash db/tests/test_004_concurrency.sh
```

Pruebas notables: RN-05 diferido → 409 al COMMIT sin dejar rastros; inyección
como valor de filtro → sin efecto (parametrización); DELETE con movimientos →
409 (FK RESTRICT); auditoría de precio con `usuario = 'app_rw'`; validación de
request → 400 sin valores reflejados.

## 7. Advisories y hallazgos abiertos

| Hallazgo | Estado | Detalle |
|---|---|---|
| **Fuente de identidad para la auditoría de precios** | **ABIERTO — decisión del usuario** | El contrato no define de dónde sale el `usuario` de `app.usuario` (sin header ni campo; `contratos.md` solo da el mecanismo). Hoy el router manda `""` → la base aplica el fallback documentado y la auditoría registra `app_rw` (verificado empíricamente). Opciones: (a) header opcional tipo `X-Usuario` (cambio de contrato), (b) campo en `VinoUpdate` (cambio de contrato), (c) mantener el rol de aplicación hasta que haya autenticación. |
| `docs/contratos.md:105` dice fallback `current_user` pero el SQL (005:483) usa `session_user` | ABIERTO — corrección documental de P1 | El comportamiento real (empírico) registra el rol de conexión (`app_rw`), que es lo deseable; la doc está desalineada. |
| Repetir `terminar` sobre un documento `terminado` es un no-op (el trigger de transiciones no se dispara si el UPDATE no cambia `estado`) | ABIERTO — decisión para 6.9 | ¿409 o idempotencia? Verificado empíricamente; los tests afirman el comportamiento real. |
| Rótulos S del contrato ≠ numeración de `consultas/select.sql` | menor | Los reportes alinearon SEMÁNTICA con select.sql; al implementar 6.10 confirmar con P2. |
| Texto informativo del OpenAPI dice «~20 rutas» pero hay 25 operaciones | menor (cosmético) | Pendiente de redacción. |
| `DELETE /clientes/{id}` no documenta `503` (sí lo hace `/vinos/{cod}`) | menor | Alinear en 6.7 si procede. |
| `detalle_vino_example` + `_EXAMPLE_*` en `routers/vinos.py` | pendiente de limpieza para 6.10 | NO es código muerto hoy: lo usa el stub de reportes. |
| Advisories de revisión RDD (R3-02/03/3/001/002/003, R3-1/2, R3-01, R3-4) | cerrados | Ver `docs/informe/07-api.md` (tabla de cierre). R3-04 quedó fuera de alcance, cubierto parcialmente por los tests del seam de errores. |

## 8. Coordinación con P1, P2 y P4

- **P1**: (a) corregir `docs/contratos.md` (`session_user` vs `current_user`); (b) definir la semántica de `terminar` repetido para 6.9; (c) confirmar que la RN-14 se satisface con las FK RESTRICT (verificado con `auditoria_precio`); (d) 6.14 revisión de seguridad/lógica.
- **P2**: (a) confirmar la semántica de S1/S6/S7/S8 usada por `repos/reportes.py` (numeración distinta en `select.sql`); (b) si las consultas cambian, re-alinear `reportes.py`.
- **P4**: (a) agregar `POSTGRES_HOST` y `DB_USER` a `.env.example` (propuesta ya documentada en `07-api.md`); (b) el CI todavía no ejecuta `pytest api/tests` (instalar `api/requirements.txt` en el workflow); (c) integrar el front contra los 6 endpoints reales y las respuestas `Error`; (d) **la decisión de identidad de auditoría afecta al front** (si se elige header/campo, el front debe mandarlo).
- **Equipo**: decidir cómo commitear el worktree actual (fronteras sugeridas en §1) — hoy está todo sin commit por instrucción.

## 9. Documentación y guía de estudio

- `docs/informe/07-api.md` — informe técnico por tarea (A + 6.1–6.6 + corrección 400 + cierre de advisories).
- `../guiaEstudioBDD.md` — guía personal de estudio: §13 (fase 6 completa), §14 (repositorios), §15 + actualización P3-12 (endpoints y validación 400), §16 (CRUD de vinos). Cada sección trae conceptos y preguntas de defensa.
- `docs/contratos.md`, `docs/tablero.md`, `docs/trazabilidad.md` — contratos y estado del equipo.
- `api/openapi.yaml` — contrato vigente (25 operaciones, lint verde).

## 10. Cómo retomar en una sesión nueva (próxima tarea: 6.7)

1. **Verificar estado**: `git branch --show-current` (debe ser `feature/p3-api-fase6`), `git log --oneline -1` (`5998f53`), `git status --short` (debe listar los archivos de §1 — si algo falta, no continuar). Confirmar que la suite pasa antes de tocar nada (`136 passed` con la receta de §6).
2. **Decidir los commits** del worktree (fronteras de §1) — o continuar sin commitear si la instrucción sigue vigente.
3. **6.7 CRUD de clientes**: los repos `clientes.py` ya existen (listar/obtener/crear/actualizar/eliminar, con subtipos y permisos) y están probados. Cablear `routers/clientes.py` siguiendo el patrón de `routers/vinos.py`:
   - `GET /clientes` (paginación + filtros `tipo`, `id_localidad`, `q`) → `listar_clientes` + `PageMeta`;
   - `GET /clientes/{id}` → `obtener_cliente` (404 con `codigo: NOT_FOUND`);
   - `POST /clientes` → `crear_cliente` (201; **nunca** enviar `descuento` ni `id_cliente`; los subtipos van en la misma transacción);
   - `PUT /clientes/{id}` → `actualizar_cliente` (`exclude_unset`; **no** cambiar `tipo`);
   - `DELETE /clientes/{id}` → `eliminar_cliente` (204/404/409 por FK RESTRICT de comprobantes).
4. Quitar las 5 filas de `/clientes` de `api/tests/test_stubs.py` y crear pruebas HTTP en `api/tests/test_clientes_endpoints.py` copiando el patrón de `test_vinos_endpoints.py` (fixtures con marcadores únicos, catálogos vía superuser, todo lo demás como `app_rw`).
5. Revisar `api/openapi.yaml` para los status exactos de cada operación de clientes (el contrato documenta `descuento` solo como salida — ver tarea A).
6. Ejecutar la suite completa y el lint; actualizar `docs/informe/07-api.md` y `../guiaEstudioBDD.md`.
7. Pendientes tras 6.7: 6.8 comprobantes (patrón transaccional ya en `crear_comprobante`), 6.9 transferencias/ingresos (definir `terminar` repetido), 6.10 reportes (alinear S con P2 y limpiar `detalle_vino_example`), 6.11–6.13, y la decisión de identidad de auditoría (§7).
