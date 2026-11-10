# Informe final · TPI «Bodegas del Atuel»

| Dato | Valor |
|---|---|
| Materia | Bases de Datos · Ingeniería en Sistemas · 3.° año |
| Institución | UTN Facultad Regional San Rafael |
| Ciclo | 2026 |
| P1 · Datos-Núcleo | Alejo Basile |
| P2 · Datos-Volumen | Mateo Vergara |
| P3 · API | Ivan Malaniuk |
| P4 · Front e Infraestructura | Benjamin Diaz |
| Tarea | 9.2 · Informe final · Responsable: P3 (Ivan Malaniuk) |

**Alcance.** Consolidación de los informes de `docs/informe/` con la estructura de la sección 10.2 del
enunciado; cada capítulo resume sus fuentes con rutas exactas y no reemplaza los informes parciales, que
conservan el detalle.

**Semántica de estado.** Se usa la misma convención que los informes fuente: **Hecho** (entregable presente y
verificado), **Parcial** (existe pero le falta una pieza declarada), **Pendiente** (no existe o no se ejecutó)
y **No verificable** (no hay evidencia auditable en el repositorio ni en GitHub). Las cifras se citan de la
fuente indicada; no se agregaron fechas, hashes ni resultados nuevos.

## 1. Introducción

### 1.1 Contexto del proyecto

«Bodegas del Atuel» es el trabajo práctico integrador de Bases de Datos: un sistema de gestión y distribución
vitivinícola en el que la base de datos es el componente central. El proyecto modela bodegas, fincas,
parcelas, cepas, vinos, salas de venta, clientes con subtipos, comprobantes, ingresos, transferencias y stock;
implementa las reglas de negocio en PostgreSQL y expone los datos con una API REST y un front que consumen el
contrato. El plan oficial divide el trabajo en diez fases (0 a 9) y asigna la capa de datos el 70 % del peso
de la evaluación.

El repositorio sigue la estructura de la sección 10.1 (`db/migrations/`, `db/seed/`, `db/tests/`,
`consultas/`, `api/`, `front/`, `scripts/`, `docs/`); `.env` está ignorado desde el primer commit
(`docs/informe/00-arranque.md`).

### 1.2 Equipo, roles y metodología

Los roles son fijos y lo que rota es el revisor de cada PR, según el plan: P1 es dueño del DER, el esquema,
las constraints, las funciones, los triggers, los tests de reglas y las consultas UPDATE e INSERT; P2 de los
catálogos, los procedimientos, la carga masiva, los índices, las consultas SELECT y la concurrencia; P3 del
OpenAPI, las vistas y roles, la API, sus pruebas, la consulta DELETE y la consolidación del informe; P4 del
repositorio, Docker, el CI, el front, la nube, los backups y el README.

La metodología descansa en contratos primero, un dueño por archivo y mocks o datasets reducidos para no
bloquear a otros; la cadena de revisión es P1 → P2 → P3 → P4 → P1 y la plantilla de PR exige tarea, pruebas,
párrafo del informe y confirmación de que no hay secretos.

El contrato técnico fija `snake_case` sin tildes, claves `id_<entidad>`, dinero en `NUMERIC(12,2)`,
porcentajes en `NUMERIC(5,2)`, errores de regla con `RAISE EXCEPTION '[RN-xx] …'` (SQLSTATE `P0001`, traducido
a HTTP 409) y la regla de que la API envía solo `(cod_vino, cantidad)` en los renglones (`docs/contratos.md`).

### 1.3 Stack efectivamente usado

| Capa | Tecnología | Versión | Evidencia |
|---|---|---|---|
| Base de datos | PostgreSQL | 16 (`postgres:16-alpine`); probado en 14.24 y 18.6 | `docker-compose.yml`, PR #2, `docs/informe/08-nube.md` |
| Contenedores | Docker y Docker Compose | v2 | `docker-compose.yml` |
| API | FastAPI | 0.162.2 | `api/requirements.txt` |
| Servidor ASGI | Uvicorn | 0.54.0 | `api/requirements.txt` |
| Driver | psycopg (binario) | 3.3.8 | `api/requirements.txt`, `api/openapi.yaml` |
| Pool | psycopg-pool | 3.3.3 | `api/requirements.txt` |
| Pruebas de API | pytest + httpx | 9.2.0 / 0.28.1 | `api/requirements.txt` |
| Front | JavaScript modular + Vite | Vite 8.3.6, sin framework | `front/package.json`, `front/src/main.js` |

La tarea 0.4 quedó **Parcial**: el stack está implementado y la restricción «driver nativo y sin ORM» está
anotada en el README, pero no existe un issue formal de decisión con votación de 24 horas y la sección `##
Stack` del README no nombra FastAPI, psycopg ni Vite (`docs/informe/00-4-decision-stack.md`). El front real es
JavaScript modular con Vite, **no React** como recomendaba el enunciado; no hay acta que registre esa
diferencia.

### 1.4 Arranque común, CI y consultas al docente

`docker-compose.yml` define PostgreSQL 16 con volumen nombrado, healthcheck y `db/migrations/` montado en
`/docker-entrypoint-initdb.d`; `scripts/reset_db.sh` recrea la base y espera `healthy`. La verificación del
2/11/2026 confirmó PostgreSQL 16.15 y el orden alfabético de migraciones (`docs/informe/00-arranque.md`); el
pre-chequeo de nube (0.6) está en `docs/informe/08-nube.md`.

La tarea 1.8 dejó un workflow de dos jobs: `db` aplica las migraciones y verifica 29 tablas, 4 vistas y los
roles `bda_owner`, `app_rw` y `reporte_ro` (`tablas=29, vistas=4, roles=3`; contra base vacía devuelve
`exit=3`), y `contrato` valida el OpenAPI con Redocly y prueba `GET /salud` con Prism. Los cinco bocetos están
en `docs/bocetos/` (`docs/informe/01-8-ci-mock-bocetos.md`).

La tarea 0.5 está **Pendiente**: `docs/decisiones.md` no existe y no hay evidencia de envío ni respuesta
(`docs/informe/00-5-consultas-docente.md`). La 0.7 quedó **Parcial**: el informe de arranque registra el
commit inicial de P4 y deja pendientes los otros tres; GitHub muestra PRs de los cuatro integrantes, pero no
un primer commit identificado como tal.

### 1.5 Estado del capítulo

| Tarea(s) | Estado | Evidencia clave |
|---|---|---|
| 0.1 Repositorio y tablero | Hecho | Estructura de la sección 10.1, `.gitignore`, `.env.example`, plantilla de PR, `docs/tablero.md` |
| 0.2 Docker Compose inicial | Hecho | PostgreSQL 16.15, volumen, healthcheck, `reset_db.sh`; orden 001→002 probado |
| 0.3 Convenciones y contrato | Parcial | `docs/contratos.md` presente; `docs/convenciones.md` no existe |
| 0.4 Decidir stack | Parcial | Stack implementado; sin issue de decisión ni stack concreto en README |
| 0.5 Consultas al docente | Pendiente | `docs/decisiones.md` ausente |
| 0.6 Pre-chequeo de nube | Hecho | `docs/informe/08-nube.md` |
| 0.7 Primer commit de cada integrante | Parcial | Solo el de P4 queda registrado en el informe de arranque |
| 1.8 CI, mock y bocetos | Hecho | `db` 29/4/3, `contrato` con Redocly y Prism; 5 SVG |

## 2. Modelo

### 2.1 Alcance y fuentes

El capítulo cubre el DER, el esquema relacional, el esquema físico `001_esquema.sql`, los catálogos, la
normalización a 3FN, el diccionario de datos, las decisiones de diseño y el contrato técnico. Las fuentes son
`docs/informe/01-modelado.md`, `docs/justificaciones.md`, `docs/normalizacion.md`, `docs/diccionario.md`,
`docs/contratos.md`, `db/migrations/001_esquema.sql` y `api/openapi.yaml`.

Una salvedad de trazabilidad: `docs/informe/01-modelado.md` contiene solo las secciones de P2 (1.4 a 1.6). El
informe del DER y del esquema relacional no está en ese archivo, y en `docs/` no aparecen `DER.drawio`,
`DER.pdf` ni `esquema_relacional.md`. El esquema físico sí existe y es la fuente verificable del modelo
implementado. Por eso el DER y la justificación formal de las cinco decisiones se consideran **No verificables
como entregables escritos**; las decisiones de diseño sí están en `docs/justificaciones.md`.

### 2.2 Esquema físico `001_esquema.sql`

`db/migrations/001_esquema.sql` se incorporó en el PR #1 («feat(db): esquema físico 001 con 29 tablas y 34
FK»), mergeado el 2026-11-05 16:20:08 UTC. El archivo define el tipo `estado_documento` (`en_confeccion`,
`terminado`, `procesado`), el dominio `cuit_dom` (`varchar(11)`) y 29 tablas con sus claves primarias y
foráneas en orden de dependencia. Los importes usan `NUMERIC(12,2)`, los porcentajes `NUMERIC(5,2)` y
`vino.cod_vino` es `GENERATED ALWAYS AS IDENTITY` (PR #12).

La revisión de P3 quedó APPROVED el 2026-11-05 16:19:54 UTC con cuerpo vacío: **no hay observaciones
escritas** que P1 pudiera resolver, así que ese criterio es **No verificable**. Las observaciones registradas
son del review de P2 sobre `002_constraints.sql` (PR #5), canalizadas en el issue #6
(`docs/informe/01-7-openapi.md`).

### 2.3 Catálogos CSV

P2 generó los catálogos de `db/seed/catalogos/` a partir del Anexo B y de los códigos postales de Mendoza:
`cepas.csv` (12 filas: 7 tintas y 5 blancas), `maridajes.csv` (8), `localidades_mendoza.csv` (18 departamentos
con código postal de cuatro dígitos único), `tipos_vino.csv` (4) y `presentaciones.csv` (5). Los archivos son
UTF-8 sin BOM, con separador coma y cabeceras en `snake_case`.

Los catálogos no incluyen IDs: las claves subrogadas las genera PostgreSQL y el orden de carga es fijo
(`cepas` → `maridajes` → `localidades`). El encargado regional se completa en `seed.py` con Faker `es_AR` y
semilla fija, no en el CSV. Una recarga con `TRUNCATE ... RESTART IDENTITY CASCADE` conserva los mismos IDs y
el mismo contenido (`docs/informe/01-modelado.md`).

### 2.4 Normalización y diccionario

`docs/normalizacion.md` se reescribió desde el esquema físico real: dependencias funcionales de las 29
relaciones y demostración de 1FN (atributos atómicos, renglones y tablas `N:M`), 2FN (claves compuestas) y 3FN
(localidad → encargado regional, subtipos, FK y derivados por triggers), con las claves candidatas `UNIQUE` y
la justificación de que departamento y provincia en `finca` son atributos descriptivos.

`docs/diccionario.md` se generó desde `information_schema` y `pg_catalog` sobre PostgreSQL 16.15: **29 tablas,
125 columnas, 29 PK y 34 FK** con tipo físico, nulabilidad, default, restricciones y descripción. Debe
regenerarse cuando `002_constraints.sql` agregue `CHECK`, `UNIQUE`, `DEFAULT` y `NOT NULL`; esa regeneración
no está evidenciada.

### 2.5 Decisiones de diseño

`docs/justificaciones.md` documenta las decisiones estructurales:

| Decisión | Implementación |
|---|---|
| Jerarquía de clientes | Supertipo `cliente` con discriminador `tipo` y subtipos `socio`, `distribuidor` y `exportador`; PK del subtipo = FK al supertipo. Evita columnas nulas y garantiza por estructura que un socio no tenga permisos de exportación. |
| Claves | Subrogadas (`IDENTITY`) en la mayoría de las tablas; naturales en `bodega` y `empleado` (CUIT); compuestas en tablas débiles e intermedias (`parcela`, `renglon_comprobante`). |
| Derivados | Se almacenan `precio_unitario`, `descuento`, `subtotal` y `total`; los mantienen triggers. `cliente.descuento` es una columna generada desde `tipo` (R-002). La antigüedad se calcula al vuelo con `fn_antiguedad_anios`. |
| Acciones referenciales | `RESTRICT` en movimientos y catálogos (RN-14); `CASCADE` en renglones, permisos, composición y análisis; `ON UPDATE CASCADE` en las FK. |
| Ubicación de reglas | `CHECK` para reglas de una fila, `UNIQUE`/`FK` para unicidad y existencia, triggers y procedimientos para reglas que miran otras tablas. |

La consecuencia del descuento generado es que no se puede fijar un porcentaje distinto por cliente individual:
el porcentaje queda determinado por RN-06 (socio 10 %, distribuidor 20 %, exportador 30 %). El tradeoff está
aceptado en el documento.

### 2.6 Contrato técnico y OpenAPI borrador

`docs/contratos.md` fija convenciones, semántica de tipos, interacción con la API, flujos operativos, firmas
de funciones y procedimientos y datasets de prueba: es lo que permite trabajar en paralelo sin esperar el
código de otro.

`api/openapi.yaml` entró en el PR #2 («agrega OpenAPI, borrados D1-D6, vistas y roles», mergeado el 2026-11-05
23:41:47 UTC) con OpenAPI 3.0.3, **20 rutas**, 34 esquemas y 1552 líneas agregadas; cubre salud, vinos,
clientes, comprobantes, transferencias, ingresos y reportes. Es el borrador de 1.7: en la Fase 6 el contrato
creció a **26 operaciones** (25 iniciales más `/salud`) y se cotejó contra las rutas reales
(`docs/informe/07-api.md`).

### 2.7 Estado del capítulo

| Tarea(s) | Estado | Evidencia clave |
|---|---|---|
| 1.1 DER | No verificable | No hay `DER.drawio` ni `DER.pdf` en `docs/` |
| 1.2 Esquema relacional y decisiones | Parcial | Decisiones en `docs/justificaciones.md`; falta `docs/esquema_relacional.md` |
| 1.3 `001_esquema.sql` | Hecho | PR #1; 29 tablas, 34 FK, enum y dominio |
| 1.4 Catálogos CSV | Hecho | 12/8/18/4/5 filas, UTF-8, orden fijo |
| 1.5 Normalización 3FN | Hecho | `docs/normalizacion.md`, 29 relaciones |
| 1.6 Diccionario | Parcial | 29 tablas / 125 columnas; pendiente regenerar tras 002 |
| 1.7 OpenAPI borrador | Hecho con salvedad | PR #2, 20 rutas, 34 esquemas; revisión de 001 sin comentarios |
| 1.9 Revisión cruzada H1 | Parcial | APPROVED sin cuerpo; observaciones no auditables |

## 3. Integridad

Este es el capítulo de mayor peso técnico: reúne constraints, funciones, procedimientos, triggers, pruebas de
reglas, vistas, roles, runner, concurrencia y trazabilidad. La guía «dónde va cada regla» surge de
`docs/justificaciones.md` y `docs/contratos.md`: `CHECK` para una fila, `UNIQUE`/`FK` para unicidad y
existencia, triggers y procedimientos para reglas que dependen del estado de otras tablas.

### 3.1 Constraints `002_constraints.sql`

La migración se aplica sobre `001_esquema.sql` y agrega `NOT NULL`, `UNIQUE`, `CHECK` y `DEFAULT` sin
modificar las PK. Solo redefine las tres FK de los subtipos de cliente para incluir `tipo` en la jerarquía.
Los mínimos de la consigna quedaron superados:

| Requisito | Mínimo | Implementado |
|---|---:|---:|
| UNIQUE adicionales a las PK | 4 | 10 |
| CHECK | 8 | 38 (37 de tabla + 1 de dominio) |
| CHECK cruzado entre columnas | 1 | 2 |
| DEFAULT | 3 | 12 |

Los dos CHECK cruzados son `ck_permiso_fechas` (`fecha_vencimiento > fecha_emision`) y `ck_comprobante_total`
(`total = subtotal - descuento`). Ningún CHECK usa `CURRENT_DATE` ni funciones no deterministas; esas reglas
quedan en los triggers de `005_triggers.sql`.

Dos decisiones semánticas importan para la API: `cliente.descuento` es un porcentaje generado desde `tipo`,
mientras que los descuentos de comprobante y renglón son importes, por eso `ck_renglon_comprobante_descuento`
no usa `BETWEEN 0 AND 100` (un descuento de $150 es válido); y la FK compuesta `(id_cliente, tipo)` con `ON
UPDATE RESTRICT` impide cambiar el tipo mientras exista la fila del subtipo
(`docs/informe/02-constraints.md`).

### 3.2 Funciones, procedimientos y triggers

Las rutinas se incorporaron en PRs sucesivos: PR #8 (`003_funciones.sql`), PR #10 (`004_procedimientos.sql`),
PR #11 (`005_triggers.sql`) y PR #14 (inmutabilidad de `renglon_comprobante` mediante T9). La evidencia
disponible en los informes permite afirmar lo siguiente:

| Objeto | Rol | Evidencia |
|---|---|---|
| `fn_descuento_cliente(tipo)` | Devuelve 10/20/30 % según el tipo; alimenta la columna generada | `001_esquema.sql`, PR #8, `docs/informe/02-constraints.md` |
| `fn_total_comprobante(nro)` | Recalcula subtotal, descuento y total de una cabecera | `docs/informe/03-concurrencia.md`, `docs/trazabilidad.md` |
| `fn_stock_sala(sala, vino)` | Stock disponible de un vino en una sala | `docs/contratos.md`, `docs/trazabilidad.md` |
| `fn_antiguedad_anios(fecha)` | Antigüedad en años; usada por U2 y D3 | `docs/contratos.md`, `docs/informe/07-api.md` |
| `sp_procesar_ingreso(cod)` | Valida estado, mueve stock y cambia a `procesado` | PR #10, `docs/informe/03-concurrencia.md` |
| `sp_procesar_transferencia(nro)` | Ídem para transferencias, con locks en orden de `cod_vino` | PR #10, `docs/trazabilidad.md` |
| T1/T2 | Calculan importes de línea, validan stock y descuentan; recalculan cabecera | `005_triggers.sql`, RN-08/RN-09 |
| T3/T4/T5/T6 | Transiciones de estado, inmutabilidad de cabecera, fecha de transferencia y bloqueo de claves de renglón | `005_triggers.sql`, RN-10/RN-11/RN-12 |
| T7 | Auditoría de precio con `app.usuario` o `session_user` | `005_triggers.sql`, RN-13 |
| T9 | Inmutabilidad adicional de `renglon_comprobante` | PR #14 |
| `tg_composicion_cien` | Constraint trigger diferido que exige suma 100 (RN-05) | `005_triggers.sql` |

Hallazgo relevante **R-001**: con triggers `SECURITY INVOKER`, `app_rw` necesitaba `UPDATE`/`DELETE` sobre
tablas sensibles y podía saltarse los triggers. La corrección pasó T1, T2, T7 y los dos procedimientos a
`SECURITY DEFINER` con `SET search_path = pg_catalog, public` y redujo `app_rw` a la matriz mínima; la
auditoría registra `app.usuario` o `session_user`, nunca `current_user`, que dentro de `DEFINER` es el dueño
(`docs/informe/02-constraints.md`).

### 3.3 Pruebas de reglas

`db/tests/db_tests.sql` valida 11 casos sobre `002_constraints.sql`: UNIQUE, CHECK (incluidos los dos
cruzados), DEFAULT, semántica de importes del descuento, jerarquía de clientes y formato del código postal.
Los casos válidos insertan y verifican; los inválidos esperan el SQLSTATE (`23514`, `23505`, `23503`) y fallan
si la operación no es rechazada. Dos corridas consecutivas terminaron con `EXIT=0` sobre PostgreSQL 16
(`docs/informe/02-tests-constraints.md`).

La suite completa de reglas cubre RN-01 a RN-15. `db/tests/db_tests.sql` prueba las reglas de constraints y
triggers; `security_r001.sql` cubre R-001; `test_004_concurrency.sh` cubre RN-11/RN-12 bajo concurrencia real.
Las pruebas de RN-10, RN-11 y RN-12 confirman transiciones válidas e inválidas, bloqueo de renglones fuera de
`en_confeccion` y cascada sin error (`docs/informe/02-8-runner-tests.md`).

### 3.4 Vistas y roles

`006_vistas.sql` (219 líneas) define **cuatro vistas convencionales**: `vw_stock_total_vino`,
`vw_ventas_mensuales_sala`, `vw_documentos_pendientes` y `vw_ficha_vino`. El plan pedía tres y permitía una
materializada; ninguna lo es porque el stock y las ventas cambian en cada operación y el volumen no justifica
el `REFRESH`. La cuarta vista soporta S9 y el detalle de vino de la API.

`007_roles.sql` (464 líneas) crea `bda_owner`, `app_rw` y `reporte_ro` con `NOLOGIN`; las contraseñas se
asignan con `scripts/set_role_passwords.sh` desde variables de entorno. Revoca privilegios a `PUBLIC` en
esquema, tablas, vistas, secuencias, rutinas y base; `app_rw` recibe `SELECT`/`INSERT`/`UPDATE`/`DELETE`
mínimos por tabla y columna, sin DDL, sin `USAGE` de secuencias y sin `UPDATE`/`DELETE` sobre
`renglon_comprobante`; `reporte_ro` solo lee las cuatro vistas y seis tablas justificadas.

El PR #13 agregó `test_006_vistas.sql` (A1–A5); el PR #15 cambió `ON ALL TABLES` por `GRANT`/`REVOKE`
explícitos y agregó `test_007_roles.sql` con denegaciones vivas `42501`; el PR #22 corrigió R-015,
R-001/R-005, R-011, R-012 y R-013 y documentó 8 OK de vistas, 38 OK de roles, 94 OK de `db_tests.sql` y 97 OK
sobre `main` en PostgreSQL 16.15, **no re-ejecutados en esta sesión**.

Riesgo residual: `ALTER DEFAULT PRIVILEGES` concede `SELECT` a `reporte_ro` sobre toda tabla futura; el
archivo lo asume y acotarlo es decisión de equipo (`docs/informe/02-5-vistas-roles.md`).

### 3.5 Runner de tests y CI

`scripts/run_db_tests.sh` centraliza cinco suites: `test_007_roles`, `test_006_vistas`, `security_r001`,
`db_tests` y `test_004_concurrency`. Carga `.env`, exige el contenedor `db` sano, imprime PASS/FAIL por suite,
continúa ante un fallo para dar un panorama completo y devuelve exit 1 si algo falló. `--reset` recrea la base
y `--verbose` muestra la salida completa. El CI agregó el job «Tests de reglas» con `./scripts/run_db_tests.sh
--reset`.

La línea base dio `Suites: 5 | PASS: 5 | FAIL: 0`. La prueba negativa revocó `EXECUTE` de
`fn_descuento_cliente(varchar)` a `app_rw` y el runner devolvió `FAIL` con `runner_exit=1`. La primera
ejecución real del job en el PR #28 falló por una carrera en `test_004_concurrency.sh`; se agregó una barrera
que espera a que la sesión C esté durmiendo con el lock tomado y el runner volvió a `5/5`
(`docs/informe/02-8-runner-tests.md`).

### 3.6 Concurrencia

La demostración de `docs/informe/03-concurrencia.md` se hizo con PostgreSQL 16, `READ COMMITTED`, dos procesos
`psql` y `stock_sala.cantidad = 1`:

| Escenario | Mecanismo | Resultado |
|---|---|---|
| 1 · Venta sin lock | Lectura y escritura separadas en el tiempo | Dos ventas confirmadas, stock final `0` (*lost update*) |
| 2 · Venta con RN-09 | `SELECT ... FOR UPDATE` en el trigger BEFORE INSERT | Una sola venta; la segunda recibe `[RN-09]` |
| 3 · Transferencia con RN-12 | Lock de `stock_deposito` + bloqueo de renglones | `90 / 10 / procesado`; edición concurrente rechazada |

El escenario 1 muestra que un `CHECK (cantidad >= 0)` no alcanza: el valor final es `0`, no negativo. El
escenario 2 demuestra que el lock mantiene juntos la validación y el descuento. El escenario 3 verifica que el
documento terminado congela sus renglones y que `sp_procesar_transferencia` consume exactamente el conjunto
que validó.

### 3.7 Trazabilidad y revisiones

`docs/trazabilidad.md` tiene una fila por RN-01 a RN-15 con mecanismo, archivo y caso de prueba. Su plantilla
la creó P1 en `3dc623ca` y se completó en `7f1398ea` y el PR #17; el plan la asigna a P3, pero Git muestra que
la creó P1: la tarea 2.10 es **contradicción con el plan**, no incumplimiento de P3
(`docs/informe/revisiones-p3.md`).

La revisión de 2.5 asignada a P4 no tiene review en GitHub; la aprobación del PR #2 es de MaJuVer (P2), y el
`CHANGES_REQUESTED` del PR #5 también es de P2: cuatro bloqueantes sobre `localidad`, `vino.cod_vino`, la
semántica del descuento y la falta de pruebas e informe de 2.1.

### 3.8 Estado del capítulo

| Tarea(s) | Estado | Evidencia clave |
|---|---|---|
| 2.1 Constraints | Hecho | 10 UNIQUE, 38 CHECK, 2 cruzados, 12 DEFAULT; `EXIT=0` |
| 2.2 Funciones | Hecho | PR #8; 4 funciones firmadas |
| 2.3 Procedimientos | Hecho | PR #10; 2 procedimientos con locks ordenados |
| 2.4 Triggers | Hecho | PR #11 y #14; BEFORE, AFTER y constraint trigger diferido |
| 2.5 Vistas y roles | Hecho con diferencia | PR #2/#13/#15/#22; 4 vistas, 3 roles, privilegios mínimos |
| 2.6–2.7 Tests de reglas | Hecho | `db_tests.sql`, `security_r001.sql`, `test_004_concurrency.sh` |
| 2.8 Runner de tests | Hecho | 5/5 PASS; prueba negativa exit 1; job de CI |
| 2.9 Concurrencia | Hecho | 3 escenarios documentados con salidas reales |
| 2.10 Trazabilidad | Hecho (atribución distinta) | 15 filas; plantilla creada por P1, no por P3 |
| Revisión de 2.5 por P4 | Pendiente | Sin review registrado de P4 |

## 4. Carga

### 4.1 Orden, determinismo y CLI

El orden de carga sigue la topología de FK: catálogos CSV, entidades independientes y dependientes; el
diagrama Mermaid está en `db/seed/README.md` y en `docs/informe/04-carga.md`. `db/seed/seed.py` usa
`random.seed(42)` y `Faker.seed(42)`, con escala `small` (50 comprobantes, 151 renglones) y `full` (20.000
comprobantes, ~350.000 renglones). `--fecha-base YYYY-MM-DD` fija la referencia: todas las fechas históricas
son relativas a ella, nunca absolutas.

La siembra dirigida prepara los casos de la sección 8: socios con alta mayor a cinco años (D1), socios sin
compra (D4/D6), empleados con más y menos de cinco años (U2/D3), salas con cierre lunes y miércoles (U4),
exportadores con cuatro o más permisos (U6), General Alvear y un transportista con pocos envíos (I1), tintos
de 14° o más (I2), «Malbec Reserva» de 750 ml (I6), ingresos procesados de más de 365 días (D5) y
composiciones que suman 100.

### 4.2 Estrategia frente a los triggers

Para la carga histórica se desactivan los triggers de usuario sobre `renglon_comprobante`, `comprobante`,
`ingreso`, `transferencia`, `renglon_ingreso` y `renglon_transferencia`. La ventaja es la velocidad y la
posibilidad de insertar estados `procesado`/`terminado` que los triggers rechazarían. El riesgo es que los
triggers no validan durante la carga; se compensa con `db/seed/controles.sql`, que verifica integridad
referencial, stocks no negativos, composiciones iguales a 100 y totales de comprobante consistentes. Al
terminar se recalculan los totales por conjuntos y se reactivan los triggers con `ENABLE TRIGGER USER`
(`docs/informe/04-carga.md`).

### 4.3 COPY y benchmark

Se usa `psycopg3.copy()`; `vino` es la excepción porque `cod_vino` es `GENERATED ALWAYS AS IDENTITY` y COPY no
permite override, así que se usa `INSERT ... RETURNING`. El benchmark de 5.000 filas dio:

| Método | Tiempo | Speedup |
|---|---:|---:|
| INSERT fila por fila | 3,972 s | 1x |
| COPY por lotes | 0,032 s | 125,9x |

### 4.4 Controles y reproducibilidad

`controles.sql` devuelve conteo por las 29 tablas, cero huérfanas, cero stocks negativos, cero totales
inconsistentes, cero composiciones distintas de 100 y cero estados inválidos.
`scripts/verify_reproducibility.sh` crea dos PostgreSQL efímeros, aplica 001–007, carga el seed, aplica 008 y
compara por tabla cantidad de filas y MD5 de las filas serializadas y ordenadas. Con la misma `fecha-base` dio
exit 0 y 29/29 tablas PASS; con `2026-01-01` contra `2026-02-01` fallaron 7 tablas dependientes de fechas
(`analisis_calidad`, `cliente`, `comprobante`, `empleado`, `ingreso`, `permiso_exportacion`, `transferencia`),
lo que confirma que el generador respeta la fecha base. Los PR #26 (reproducibilidad) y #21 (carga
determinista) cerraron la tarea.

### 4.5 Backup y restauración locales

El PR #21 cerró 3.7 con `scripts/seed.sh` y los controles, sin volcado. Para no bloquear 3.9,
`scripts/backup.sh` genera el dump de la base local sembrada con `pg_dump` dentro del contenedor
(`--no-owner`, `--no-privileges`, `--clean`, `--if-exists`, `--encoding=UTF8`), comprime con `gzip -9` y
genera un manifiesto `.counts`. `scripts/restore.sh` rechaza restaurar sobre `POSTGRES_DB`, exige `--recreate`
si la base destino existe, restaura con `ON_ERROR_STOP=1`, reaplica `007_roles.sql` y compara conteos con
`diff`.

La prueba sobre PostgreSQL 16.15 generó un dump de 24K con 29 tablas, lo restauró en
`bodegas_del_atuel_restore` y coincidieron los 29 conteos; las pruebas negativas devolvieron exit 1 al
restaurar sobre la base de origen, al no pasar `--recreate` y al alterar el manifiesto. Se conservaron
`app_rw` sin `UPDATE` sobre `renglon_comprobante`, `app_rw` con `EXECUTE` y `reporte_ro` con `SELECT` sobre la
vista (`docs/informe/03-9-backup-restore.md`, PR #29).

### 4.6 Estado del capítulo

| Tarea(s) | Estado | Evidencia clave |
|---|---|---|
| 3.1 Orden de carga | Hecho | Diagrama FK en `db/seed/README.md` |
| 3.2 Script determinístico | Hecho | `seed.py`, semilla 42, `small`/`full`, `--fecha-base` |
| 3.3 Siembra dirigida | Hecho | Casos D/U/I/RN documentados |
| 3.4 Estrategia frente a triggers | Hecho | `DISABLE TRIGGER USER` + `controles.sql` |
| 3.5 COPY y benchmark | Hecho | 125,9x en 5.000 filas |
| 3.6 Controles | Hecho | 6 bloques sin errores |
| 3.7 Script y dump | Hecho | `seed.sh`; dump generado por 3.9 |
| 3.8 Reproducibilidad | Hecho | 29/29 PASS; 7 FAIL esperados con otra fecha base |
| 3.9 Backup/restore local | Hecho | 24K, 29 conteos coincidentes, 3 negativos |

## 5. Índices

### 5.1 Entorno de medición

Las mediciones se hicieron sobre PostgreSQL 16 con migraciones 001–008 y el dataset `--scale full`:
**350.000** `renglon_comprobante`, **20.000** `comprobante`, **306** `vino`, **200** `cliente`, **200**
`stock_sala` y **500** `transferencia`. Se ejecutó `ANALYZE` antes de cada ronda y se usaron S1, S4, S8 y S10
de `consultas/select.sql` como consultas de referencia (`docs/informe/05-indices.md`).

### 5.2 Diseño de `008_indices.sql`

Se crearon **7 índices** que cubren los seis tipos pedidos:

| # | Tipo | Índice | Propósito declarado |
|---|---|---|---|
| 1 | Compuesto | `idx_comprobante_sala_fecha (id_sala, fecha)` | Ventas por sala y mes |
| 2 | Parcial | `idx_transferencia_no_procesadas (id_sala, fecha_confeccion) WHERE estado <> 'procesado'` | Transferencias pendientes |
| 3 | FK no-PK + INCLUDE | `idx_renglon_comprobante_vino (cod_vino) INCLUDE (cantidad, subtotal, descuento)` | Ranking y filtro por vino |
| 3b | FK no-PK | `idx_renglon_comprobante_nro (nro_comprobante)` | JOIN con comprobante |
| 4 | Covering INCLUDE | `idx_comprobante_cliente_total (id_cliente, fecha) INCLUDE (total)` | Clientes sobre promedio |
| 5 | BRIN | `idx_comprobante_fecha_brin USING brin (fecha)` | Rango temporal |
| 6 | Covering | `idx_stock_sala_sala_cantidad (id_sala, cantidad) INCLUDE (cod_vino)` | Stock por sala |

La justificación del índice compuesto no coincide con los filtros de la S1 publicada: S1 no tiene `WHERE` y
agrupa y ordena todas las ventas por sala y mes, así que el orden `(id_sala, fecha)` queda como diseño
propuesto, no como optimización demostrada. Se descartó `idx_comprobante_descuento`: S1 suma `rc.descuento` y
no filtra por descuento, y el índice solo agregaría costo de escritura.

### 5.3 Medición «antes» y «después» original

| Consulta | Antes (ms) | Después (ms) | Δ | Plan original |
|---|---:|---:|---|---|
| S1 · Ventas por sala y mes | 4.946 | 3.332 | −33 % | Seq Scan + Sort en disco (15 MB) |
| S4 · Ranking de vinos | 555 | 1.066 | +92 % | Parallel Seq Scan |
| S8 · Stock por sala | 2,4 | 2,6 | +8 % | Seq Scan (200 filas) |
| S10 · Clientes sobre promedio | 4.175 | 4.594 | +10 % | Seq Scan + subconsulta correlacionada |

### 5.4 Reproducción independiente (4.7)

La revisión cruzada de 4.7 no reprodujo la mejora de S1: en su corrida S1 pasó de 488,426 a 507,588 ms (+3,9
%) con el mismo `GroupAggregate`, Seq Scans y Sort externo de 15.768 kB. S4 pasó de 77,771 a 120,518 ms (+54,9
%) conservando `Parallel Seq Scan`; S8 bajó de 0,389 a 0,378 ms y S10 subió de 514,473 a 562,328 ms (+9,3 %).
La conclusión honesta del informe es que la afirmación general «los índices mejoran S1» queda **no
reproducida**; los tiempos absolutos dependen del entorno y la repetición disponible no basta para establecer
causalidad.

### 5.5 Costo de escritura

La medición original informó 0,032 s sin índices secundarios y 0,089 s con los siete índices (+178 %). La
reproducción observó 132,498 ms y 142,841 ms (+7,8 %): se reproduce la dirección del efecto —mayor costo con
índices—, no su magnitud. La estrategia recomendada para volúmenes altos es cargar sin índices secundarios,
crear los índices y ejecutar `ANALYZE`.

### 5.6 El planificador y el índice que no se usa

S4 agrega todas las filas de `renglon_comprobante` y el planificador elige `Parallel Seq Scan`: cuando se lee
más del ~20 % de una tabla, el escaneo secuencial evita el costo de buscar cada fila en el índice y luego en
el heap. Con un filtro selectivo (`WHERE cod_vino = 5`) el índice sí se usa; la reproducción observó `Bitmap
Heap Scan` con `Bitmap Index Scan on idx_renglon_comprobante_vino`. Aplicar `008_indices.sql` por segunda vez
terminó sin error: la migración es idempotente por `IF NOT EXISTS`.

### 5.7 Estado del capítulo

| Tarea(s) | Estado | Evidencia clave |
|---|---|---|
| 4.1 Medición antes | Hecho | 4 consultas con tiempo y plan |
| 4.2 Diseño de índices | Hecho | 7 índices, 6 tipos, comentarios |
| 4.3 Medición después | Hecho con salvedad | Tabla comparativa; mejora de S1 no reproducida |
| 4.4 Orden y descarte | Hecho | Orden `(id_sala, fecha)` y descarte de `idx_comprobante_descuento` |
| 4.5 Costo de escritura | Hecho con salvedad | +178 % original, +7,8 % reproducido |
| 4.6 Planificador | Hecho | `Parallel Seq Scan` en S4 y uso con filtro selectivo |
| 4.7 Revisión cruzada | Hecho | Reproducción documentada; idempotencia de 008 |

## 6. Consultas

### 6.1 Fuentes y método

Las consultas de la sección 8 viven en `consultas/select.sql`, `consultas/update.sql`, `consultas/insert.sql`
y `consultas/delete.sql`. **No existe un informe dedicado de las consultas SELECT, UPDATE e INSERT**: la
evidencia son los archivos SQL, sus encabezados y los PRs #24 y #27. El DELETE sí tiene detalle en la sección
«Tarea E» de `docs/informe/07-api.md`. Cada archivo documenta el código, el enunciado, la estrategia, los
parámetros modificables y un bloque de control previo y posterior; las sentencias que modifican datos se
ejecutan dentro de `BEGIN … ROLLBACK` para no destruir el dataset.

### 6.2 SELECT S1–S12

`consultas/select.sql` contiene S1–S12 (PR #24, tareas 5.4 y 5.5). S1, S4, S8 y S10 son la referencia de
benchmark de la Fase 4; S2, S3, S5, S6 y S7 se integraron desde P4. La cobertura es: ventas por sala y mes,
clientes con mayor facturación, clientes por tipo, ranking de vinos, salas con menos transferencias
pendientes, vinos sin stock en sala pero con stock en depósito, transportista más activo, ventas mensuales,
ficha de vino, clientes sobre el promedio con CTE, ranking con `RANK() OVER` y suma acumulada, y división
relacional con `NOT EXISTS`.

El encabezado de S1 muestra el patrón: `JOIN` de `comprobante × renglon_comprobante × sala`, `GROUP BY
s.id_sala, date_trunc('month', c.fecha)`, `ORDER BY s.id_sala, mes`. El archivo no incluye salidas; la
ejecución completa sobre `full` queda pendiente.

### 6.3 UPDATE U1–U6

`consultas/update.sql` (PR #27) contiene:

| Código | Consigna | Mecanismo |
|---|---|---|
| U1 | Recalcular totales de todos los comprobantes | Reutiliza `fn_total_comprobante` |
| U2 | Aumentar salarios según antigüedad | `fn_antiguedad_anios` |
| U3 | Subir el precio de los vinos de una bodega | Dispara RN-13 (auditoría de precio) |
| U4 | Intercambiar el día de cierre lunes ↔ miércoles | Un solo `UPDATE` con `CASE` |
| U5 | Aplicar 15 % de descuento a los 10 vinos menos vendidos | Subconsulta de ranking |
| U6 | Prorrogar un año los permisos de exportadores con más de 3 permisos | `HAVING COUNT(*) > 3` |

### 6.4 INSERT I1–I6

`consultas/insert.sql` (PR #27) contiene: I1, cobertura General Alvear ↔ transportista con menos envíos del
último trimestre (subconsulta); I2, alta del maridaje «cordero al disco» asociado a los tintos de 14° o más;
I3, comprobante con tres renglones que deja que los triggers calculen todo; I4, alta simple de una bodega; I5,
alta simple de una sala; I6, ingreso en confección con un renglón de 120 botellas. I3 es la consulta que mejor
muestra la división de responsabilidades: la API o el SQL envían solo `(cod_vino, cantidad)` y la base calcula
precio, descuento, subtotal, total y stock.

### 6.5 DELETE D1–D6

`consultas/delete.sql` contiene:

| Código | Consigna | Validación documentada |
|---|---|---|
| D1 | Comprobantes de más de 5 años de socios | Los renglones caen por `ON DELETE CASCADE` |
| D2 | Cepas que no componen ningún vino ni están plantadas | `NOT EXISTS` |
| D3 | Empleados de la sala de una localidad dada, por antigüedad | Filtra con `fn_antiguedad_anios(...) < 2` |
| D4 | Socios sin compras con alta mayor a 5 años | `NOT EXISTS` |
| D5 | Ingresos procesados de hace más de 365 días | Estado `procesado` + fecha |
| D6 | Socios sin compras de una localidad | Localidad + `NOT EXISTS` |

La sección «Tarea E» de `docs/informe/07-api.md` documenta la prueba real en PostgreSQL 16 efímero. D5 ejecutó
`DELETE 1` sin SQLSTATE ni regla que lo bloqueara; el `renglon_ingreso` desapareció por cascada y **RN-12 no
bloqueó la cascada** porque el trigger salta la validación cuando la cabecera ya no existe. D3 ejecutó `DELETE
2` (empleados de −300 y −60 días) y no borró al de 1000 días. La pasada completa D1–D6 en bloques `BEGIN …
ROLLBACK` terminó sin `ERROR`; D1, D4 y D6 devolvieron `DELETE 0` porque el dataset efímero no tenía filas que
cumplieran la condición. La prueba sobre el dataset completo de seeds queda pendiente.

### 6.6 Estado del capítulo

| Tarea(s) | Estado | Evidencia clave |
|---|---|---|
| 5.1 UPDATE U1–U6 | Hecho (sin informe dedicado) | `consultas/update.sql`, PR #27 |
| 5.2 INSERT I1–I6 | Hecho (sin informe dedicado) | `consultas/insert.sql`, PR #27 |
| 5.3 DELETE D1–D6 | Hecho con salvedad | `consultas/delete.sql`, PR #2, «Tarea E» de `07-api.md`; D1/D4/D6 con 0 filas en dataset efímero |
| 5.4 SELECT S1, S4, S8–S12 | Hecho (sin informe dedicado) | `consultas/select.sql`, PR #24 |
| 5.5 SELECT S2, S3, S5–S7 | Hecho (sin informe dedicado) | `consultas/select.sql`, PR #24 |
| Ejecución completa sobre dataset `full` | Pendiente | No hay salida documentada de S1–S12 |

## 7. API y front

### 7.1 Arquitectura y regla de oro

La API se implementó con FastAPI, psycopg 3 y `psycopg_pool`, SQL puro y parametrizado, sin ORM ni query
builders, y conexión exclusivamente con el rol `app_rw`. La estructura separa routers, repositorios y
esquemas: el SQL vive en `api/app/repos/`, los routers no contienen consultas y los modelos Pydantic espejan
el contrato OpenAPI. La regla de oro se mantiene en todo el recorrido: **la API no recalcula totales,
descuentos ni stock**; esas reglas viven en triggers, columnas generadas, funciones y procedimientos. El front
tampoco calcula importes ni stock: solo formatea y muestra lo que devuelve la API.

### 7.2 Contrato, esqueleto y stubs

La «Tarea A» alineó `api/openapi.yaml` con `002_constraints.sql`: enum de cinco presentaciones (`187`, `375`,
`750`, `1500`, `3000`), `anada` entre 1990 y 2100, `graduacion` entre 5 y 20, `porcentaje` con mínimo
exclusivo, temperatura entre 0 y 30, `tipo_documento` como enum, `descuento` de cliente entre 0 y 100 y
`readOnly`, `direccion` requerida y `cantidad` mínima 1. Redocly validó el contrato con las dos advertencias
preexistentes (servidor `localhost` y `/salud` sin respuesta `4XX`).

La «Tarea B» (6.1) creó el esqueleto con `create_app`, configuración por variables de entorno, pool y `GET
/salud` con `SELECT 1` real; si la base no está disponible responde `503` con `codigo: DB_UNAVAILABLE` sin
filtrar credenciales. La «Tarea C» (6.2) publicó stubs para las 25 operaciones del contrato con `# TODO(6.x)`
y `api/tests/test_stubs.py` data-driven. La matriz de stubs se fue retirando a medida que cada endpoint se
volvió real; al cerrar 6.10 solo quedó `/salud`.

### 7.3 Manejo central de errores

`api/app/errors.py` es el único punto de conversión PostgreSQL → HTTP:

| SQLSTATE | HTTP | Comportamiento |
|---|---|---|
| `23505` unique_violation | 409 | `codigo` = SQLSTATE, `detalle` del diagnóstico |
| `23503` foreign_key_violation | 409 o 422 | Según la dirección: fila referenciada (409) o padre inexistente (422) |
| `23514` check_violation | 422 | |
| `23502` not_null_violation | 422 | |
| `P0001` raise_exception | 409 | Conserva el mensaje `[RN-xx]` y extrae `regla` |
| `P0002` no_data_found | 404 | |
| `22P02` invalid_text_representation | 400 | |
| `40001` / `40P01` | 503 | Mensaje de reintento |
| `42501` insufficient_privilege | 500 | Cuerpo genérico |
| Desconocido | 500 | Cuerpo genérico, sin texto crudo |

Clave: `transaction()` ejecuta `BEGIN … COMMIT` dentro del `try`, así que el constraint trigger diferido de
RN-05 lanza `P0001` en el `COMMIT` y también pasa por el mapeador central con `ROLLBACK` de seguridad. Los
errores de validación de FastAPI responden **400** con body `Error` (`codigo: VALIDATION_ERROR`) en lugar del
`422 {"detail": ...}`; el 422 se reserva para violaciones semánticas de la base y solo se leen `loc` y `msg`,
nunca los valores del input.

### 7.4 Capa de repositorios

`api/app/repos/` tiene **25 funciones públicas**, una por operación de acceso a datos, cada una dueña de su
conexión (`get_connection` para lecturas, `transaction` para escrituras). Todas usan SQL parametrizado (`%s` o
`%(x)s`), `RETURNING` para IDs, `dict_row` y orden determinístico. Los renglones de comprobante se insertan
ordenados por `cod_vino ASC` (regla del proyecto y orden de locks de 004). `actualizar_vino` ejecuta
`set_config('app.usuario', %s, true)` como primera sentencia de la transacción para que RN-13 audite el cambio
de precio.

La suite de repositorios observó RED por ciclo y luego GREEN, con **109 passed** (63 previas + 46 nuevas).
Cubre happy path, filtros y paginación, parametrización (`'; DROP TABLE vino; --` sin efecto), atomicidad
transaccional (RN-05 diferido, RN-09, duplicados), flujo completo de documentos, 404, reportes y fronteras de
permiso (`42501`).

### 7.5 Endpoints implementados

| Tarea | Operaciones | Resultado documentado |
|---|---|---|
| 6.5 | `GET /vinos`, `GET /vinos/{cod}` | 120 passed; filtros combinables, `PageMeta`, 404 con body `Error` |
| 6.6 | `POST`/`PUT`/`DELETE /vinos` | 136 passed; PUT parcial, DELETE con movimientos → 409, auditoría `app_rw` |
| 6.7 | CRUD `/clientes` | 153 passed; descuentos 10/20/30, subtipos y permisos, DELETE con comprobante → 409 |
| 6.8 | `POST`/`GET /comprobantes` | 159 passed; solo `(cod_vino, cantidad)`, triggers calculan todo, RN-09 atómico |
| 6.9 | 8 operaciones de transferencias e ingresos | 169 passed; estados, procedimientos, RN-10/RN-11, 404 |
| 6.10 | 5 `GET /reportes` | 174 passed; S1/S8/S6/S7/S9, solo lectura end-to-end |

Decisiones transversales documentadas: la API nunca envía `id_cliente`, `cod_vino`, `nro_comprobante`,
`fecha_confeccion` ni columnas calculadas; los `DELETE` dejan propagar las FK `RESTRICT` como error mapeado;
el `PUT` usa `exclude_unset` para actualización parcial. Quedaron decisiones abiertas: el usuario de auditoría
(hoy `usuario=""` activa el fallback `session_user`; `docs/contratos.md` dice `current_user`, el SQL usa
`session_user` y la prueba fija `app_rw`), la idempotencia de repetir `terminar` (no-op 200, no 409), el
filtro `q` de clientes (solo busca por nombre aunque el contrato promete documento) y el 404 de
`vinos-sin-stock` (el repositorio devuelve lista vacía).

### 7.6 Pruebas automáticas y CI

`api/tests/` tiene **17 archivos** `test_*.py` y **184 definiciones** `def test_` al momento de
`docs/informe/06-11-tests-api.md`. Las cinco violaciones de regla exigidas o equivalentes están cubiertas:
RN-09 → 409, RN-11 → 409, RN-10 → 409, RN-05 diferido → 409 y precio negativo → 422 (`23514`). El mínimo del
plan (8 pruebas, 3 violaciones) queda superado con amplitud.

Las cifras no coinciden entre fuentes y la reconciliación sigue pendiente: **174** en `07-api.md`, **176** en
la verificación documentada por P4 en `06-13-compose-ci.md`, **178** en el merge del PR #30 y **184** en el
conteo estático actual. La diferencia 178→184 se explica por el PR #40, que agregó seis pruebas de SSL y no
fuga de contraseña en `test_db.py`. El número exacto que reporta pytest depende de la parametrización y de las
dependencias instaladas; no se pudo correr `pytest --collect-only` en esta sesión porque el entorno no tiene
`psycopg`.

La integración al CI la cerró P4 en el PR #31: el job `api` recrea la base, instala `api/requirements.txt`,
corre `python -m pytest api/tests -q` y levanta `docker compose up -d --build` esperando `GET /salud`. La
verificación local documentada dio `176 passed` con `TZ=UTC`; siete pruebas de fecha siguen comparando
`date.today()` del host con `CURRENT_DATE` de la base y son un riesgo residual de zona horaria.

### 7.7 Inyección SQL fallida

La demostración de 6.12 se hizo con la API viva sobre PostgreSQL 16 efímero:

| Entrada | Respuesta | Estado de la tabla |
|---|---|---|
| `GET /vinos?nombre='; DROP TABLE vino; --` | 200 con `data: []` | `vino` existe, 0 filas |
| `GET /clientes?q='; DELETE FROM cliente; --` | 200 con `data: []` | `cliente` existe, 0 filas |

Los valores viajan como parámetros bound y se comparan como texto literal; los comodines `%%` del `ILIKE`
viven en el literal SQL, no en el input. La prueba automatizada equivalente está en `test_repos_vinos.py` y
`test_repos_clientes.py`.

### 7.8 Dockerfile de la API

`api/Dockerfile` usa `python:3.11-slim`, instala `api/requirements.txt` y copia solo `api/app`; el contexto de
build es la raíz del repositorio. No incluye credenciales: las variables se pasan con `--env-file`. Tiene
`HEALTHCHECK` contra `GET /salud`, que responde 503 si la base no está. El build terminó con exit 0 y sin
warnings. La coherencia OpenAPI ↔ rutas reales se cotejó con un script: **26 operaciones en el contrato, 26
rutas en la app, sin faltantes ni sobrantes**.

### 7.9 Front

El front es **JavaScript modular + Vite, sin framework**. `src/api/client.js` es la única capa que usa
`fetch`; normaliza la respuesta y convierte errores en `ApiError` conservando `codigo`, `mensaje`, `detalle` y
`regla`. La URL base es `/api` en desarrollo (proxy de Vite a Prism) y `import.meta.env.VITE_API_URL` en
build.

| Tarea | Implementación | Verificación documentada |
|---|---|---|
| 7.1 Estructura y capa de llamadas | `front/` con `client.js`, router mínimo y URL configurable | Build Vite 8.3.6; proxy contra Prism |
| 7.2 Catálogo | `GET /vinos` con filtros y paginación del servidor; detalle con composición, maridajes y stock | 4 PASS de renderizado |
| 7.3 Alta y edición | Formulario con composición dinámica; no bloquea la suma en el cliente | 13 verificaciones; banner RN-05 409 |
| 7.4 Nueva venta | Solo `id_cliente`, `id_sala` y `(cod_vino, cantidad)`; totales del backend | 9 verificaciones; banner RN-09 409 |
| 7.5 Transferencias | Botones según estado; renglones solo en `en_confeccion` | 18 verificaciones; banner RN-11 409 |
| 7.6 Tablero | Top 10, ventas por sala del trimestre y vinos sin stock | e2e con datos de la API |
| 7.7 Errores y compose | Mensajes verbatim; `front/Dockerfile` Node 24 + Nginx 1.27; servicio `front` en compose | `db`, `db-init`, `api` y `front` sanos; `/api/salud` 200 |

El front no calcula importes, descuentos ni stock. En 7.6 se detectó que la API, sin `desde` y `hasta`,
devuelve todo el historial aunque el contrato diga «último trimestre»; el front siempre envía ambos. Tampoco
existen `GET /cepas`, `/bodegas`, `/salas` ni `/transferencias/{nro}`: usa IDs y conserva el estado en
memoria.

### 7.10 Estado del capítulo

| Tarea(s) | Estado | Evidencia clave |
|---|---|---|
| 6.1 Esqueleto y `/salud` | Hecho | `SELECT 1` real, 503 saneado, 6 passed |
| 6.2 Stubs | Hecho | 25 operaciones, 32 passed |
| 6.3 Repositorios | Hecho | 25 funciones, 109 passed |
| 6.4 Errores SQLSTATE | Hecho | Tabla completa; RN-05 en COMMIT; 57 passed |
| 6.5–6.10 Endpoints | Hecho | 120/136/153/159/169/174 passed |
| 6.11 Pruebas | Hecho | 184 `def test_`; 5 violaciones de regla; CI PR #31 |
| 6.12 Inyección SQL | Hecho | Captura con tablas intactas |
| 6.13 Dockerfile y coherencia | Hecho | Build exit 0; 26/26 operaciones |
| 7.1–7.7 Front | Hecho | Builds Vite y verificaciones DOM contra API real |
| Reconciliación de cifras de tests | Pendiente | 174/176/178/184 sin `pytest --collect-only` |

## 8. Nube

### 8.1 Pre-chequeo y decisión de proveedor

La comparación del 2/11/2026 evaluó Aiven for PostgreSQL Free, Render Postgres Free, Supabase Free y Neon Free
por tarjeta, restricción por IP, red privada, almacenamiento, inactividad, conexiones, SSL, backups y
duración. El requisito —que el puerto no quede abierto a internet— descartó a Neon Free (IP Allow solo en
Scale) y a Railway (sin control por IP en el proxy TCP); la decisión fue **Aiven Free como principal** y
**Render Free como respaldo**.

Aiven no pide tarjeta, no expira, incluye un backup y permite `ip_filter` por CIDR, con 1 GB de disco, 1 CPU,
1 GB de RAM y `max_connections = 20`, sin VPC ni pooling: la API debe usar un pool pequeño. Render tiene IP
allow list en Free, 1 GB y 100 conexiones, pero la base expira a los 30 días (`docs/informe/08-nube.md`).

### 8.2 Base y roles en Aiven

La instancia real usa **PostgreSQL 18.6** (la versión del proveedor); la simulación local usó 16.15 y las
migraciones no dependen de características exclusivas de 16. El procedimiento creó el servicio y la base
`bodegas_del_atuel`, limitó el `ip_filter` y guardó las credenciales en `.env` (`CLOUD_DB_*`, `CLOUD_ADMIN_*`,
`BDA_OWNER_PASSWORD`, `DB_PASSWORD`, `REPORTE_RO_PASSWORD`).

`007_roles.sql` se aplica como administrador porque `COMMENT ON ROLE bda_owner` exige `ADMIN OPTION` o
superusuario; `migrate.sh` aplica 001–006 y 008 como `bda_owner`, 007 como administrador y quita `CREATEROLE`
al terminar. El dueño de `public` se consulta antes: solo se reclama con `aiven_extras` si no es
`pg_database_owner`, `bda_owner` ni el administrador; en el servicio real ya pertenecía a `pg_database_owner`.

La ejecución real dio `migrate.sh` exit 0 con `tablas=29, vistas=4, secuencias=13, rutinas=15, triggers=10`,
base con dueño `bda_owner`, roles `LOGIN` sin `CREATEROLE`, contraseñas desde `.env`, y una reejecución
abortada con exit 1 («el esquema ya existe»). El PR #35 cerró 8.2 y 8.3.

### 8.3 Migraciones y paridad

`scripts/migrate.sh` aplica `db/migrations/*.sql` en orden: en modo nube usa `CLOUD_DB_*` y `CLOUD_ADMIN_*`
con `sslmode=require`, y `--db-url` aplica todo con el usuario de la URL. Se niega a aplicar si
`public.localidad` ya existe, no imprime contraseñas y usa el administrador solo para crear `bda_owner`,
reclamar `public`, transferir la base y aplicar 007.

La paridad se verificó con `pg_dump 18.6 --schema-only --no-owner --no-privileges --schema=public`: ambos
dumps tienen **2168 líneas** y el `diff` solo muestra el comentario de versión y el token
`\restrict`/`\unrestrict`. La matriz de privilegios se comprobó con `has_*_privilege` y denegaciones `42501`:
`app_rw` sin `UPDATE`/`DELETE` en `renglon_comprobante`, sin `CREATE` sobre `public`, sin `USAGE` de
secuencias y con `EXECUTE` en las seis rutinas contratadas; `reporte_ro` con `SELECT` sobre la vista y sin
`INSERT` en `vino`. Aplicar 008 como `bda_owner` emite advertencias de `ANALYZE` en 18 y termina con exit 0.

### 8.4 Datos en la nube

`scripts/seed_cloud.sh` carga datos contra Aiven con `sslmode=require` y el rol `bda_owner`, y luego ejecuta
`controles.sql`. Acepta `--scale full`, `--fecha-base` y `--benchmark`. Los PRs #38 y #41 preparan la carga y
mejoran el script; la ejecución corresponde a P4 con las credenciales configuradas. La verificación esperada
es cero errores en los controles y 28 tablas con datos (`docs/informe/08-nube.md`).

### 8.5 Despliegue de la API

El plan asigna el despliegue a **P4 con apoyo de P3**. El apoyo de P3 quedó documentado en
`docs/informe/08-5-despliegue-api.md`: la API lee seis variables (`POSTGRES_HOST`, `POSTGRES_PORT`,
`POSTGRES_DB`, `DB_USER`, `DB_PASSWORD`, `POSTGRES_SSLMODE`), `POSTGRES_DB` y `DB_PASSWORD` son obligatorias,
`DB_USER` debe ser `app_rw` y en producción se usa `POSTGRES_SSLMODE=require`. `config.py` valida el modo SSL
contra una lista y no cae silenciosamente en un modo inseguro; `build_conninfo()` incluye el `sslmode`. El PR #40
dejó la configuración de SSL lista para Aiven.

Hay una **discrepancia de atribución**: `docs/informe/08-nube.md` (L157) dice que la base queda «lista para
que P3 despliegue la API», mientras que el plan asigna el despliegue a P4 con apoyo de P3. El despliegue
efectivo, la apertura del puerto, el certificado y la verificación de `GET /salud` por HTTPS son de P4 y **no
están verificados** en los informes. La instancia de Aiven existe y los roles están aplicados; la URL pública
con HTTPS sigue pendiente.

### 8.6 Backup y restauración en la nube

`docs/informe/08-backup-restore.md` documenta la política: backup local antes de cada `reset_db.sh`, backup
automático diario en Aiven con un solo backup en el plan Free y `pg_dump` manual antes de la demo. Los
comandos usan `sslmode=require` y `--no-owner --no-privileges`. La restauración en Aiven se documenta con
`psql` sobre una base nueva. El PR #25 incorporó este informe junto con el guion de demo y la lista de máquina
limpia. La restauración real en la nube no está evidenciada; la restauración local sí (capítulo 4).

### 8.7 Estado del capítulo

| Tarea(s) | Estado | Evidencia clave |
|---|---|---|
| 8.1 Elección de proveedor | Hecho | Comparativa de 4 proveedores; Aiven principal, Render respaldo |
| 8.2 Base y roles | Hecho | PG 18.6; 29/4/13/15/10; `migrate.sh` exit 0; PR #35 |
| 8.3 Migraciones y paridad | Hecho | Dumps de 2168 líneas sin diferencias; matriz de privilegios |
| 8.4 Datos | Hecho (script) / Ejecución no verificada | `seed_cloud.sh`; PR #38 y #41 |
| 8.5 Despliegue de la API | Parcial | Variables y SSL (PR #40); HTTPS y `/salud` en nube pendientes de P4 |
| 8.8 Backup y restauración | Parcial | Política y comandos documentados; restauración en nube no evidenciada |

## 9. Conclusiones

### 9.1 Síntesis por hito

| Hito | Fase | Resultado |
|---|---|---|
| H1 | Modelado | Esquema físico de 29 tablas y 34 FK, catálogos, normalización 3FN y diccionario; DER escrito no verificable |
| H2 | Integridad | 38 CHECK, 10 UNIQUE, 12 DEFAULT, 4 funciones, 2 procedimientos, triggers RN-05/08–13, vistas y roles con privilegios mínimos |
| H3 | Carga | Seed determinístico con COPY (125,9x), controles y reproducibilidad 29/29; backup/restore local con conteos |
| H4 | Índices | 7 índices de 6 tipos; mejora de S1 no reproducida y costo de escritura medido con salvedad |
| H5 | Consultas | S1–S12, U1–U6, I1–I6 y D1–D6 resueltas y comentadas; ejecución completa sobre `full` pendiente |
| H6 | API | 26 operaciones reales, errores centralizados, pruebas y demostración de inyección SQL fallida |
| H7 | Front | Catálogo, alta/edición, venta, transferencias, tablero y compose; sin lógica de negocio en el cliente |
| H8 | Nube | Aiven con base, roles, migraciones y paridad; carga preparada; HTTPS de la API pendiente |
| H9 | Cierre | Este informe; README, trazabilidad y guion de demo existen; quedan pendientes de cierre |

El proyecto demuestra el objetivo central del enunciado: la base de datos es el corazón del sistema y las
reglas viven en ella. La API y el front no duplican totales, descuentos ni stock; traducen errores y muestran
lo que la base decide. La integridad no depende del privilegio del llamador (R-001), la concurrencia está
demostrada con `FOR UPDATE` y el procesamiento de documentos es atómico.

### 9.2 Lista de control de la entrega final (sección 10.3)

| Criterio | Estado | Evidencia |
|---|---|---|
| Repositorio con commits de todos y sin secretos | Parcial | PRs de los cuatro integrantes verificados en GitHub; 0.7 no registra el primer commit de tres; `.env` ignorado y `.env.example` sin secretos, pero no hay corrida de `gitleaks` (8.7) |
| `docker compose up` levanta base, API y front en máquina limpia | Pendiente | 7.7 verificó los cuatro contenedores en el entorno de desarrollo; `09-maquina-limpia.md` tiene la checklist sin registro de ejecución |
| Migraciones en orden sobre base vacía | Hecho | `reset_db.sh`, job `db` del CI, 001–008 |
| Mínimos de constraints, funciones, procedimientos, triggers, vistas e índices | Hecho | 10 UNIQUE, 38 CHECK, 12 DEFAULT; 4 funciones; 2 procedimientos; 7 triggers; 4 vistas; 7 índices |
| Más de 100.000 filas y carga reproducible | Hecho | 350.000 renglones en `--scale full`; reproducibilidad 29/29 |
| Consultas de la sección 8 resueltas, comentadas y probadas | Parcial | SQL completo y comentado; D1/D4/D6 con 0 filas en dataset efímero; S1–S12 sin salida completa |
| Nube activa con URL pública y HTTPS | Pendiente | Aiven con base y roles; API/front por HTTPS no verificados |
| Backup restaurado en base nueva | Parcial | Local verificado con 29 conteos; nube solo documentada |
| Informe final y README completos | Parcial | Este documento cubre los 9 capítulos; README existe pero su sección de stack no nombra FastAPI, psycopg ni Vite |
| Defensa oral preparada por cada integrante | Pendiente | `docs/guion_demo.md` (9.4) existe; 9.6–9.8 sin evidencia |

### 9.3 Trabajo pendiente y riesgos

Los pendientes se agrupan en cuatro frentes:

1. **Formalidades de Fase 0.** Documentar el issue de stack (0.4), completar el
   stack concreto en el README y resolver la diferencia React/Vite; enviar las
   consultas al docente y crear `docs/decisiones.md` (0.5); crear
   `docs/convenciones.md` o asentar que `docs/contratos.md` lo reemplaza (0.3);
   registrar el primer commit de cada integrante (0.7).
2. **Trazabilidad y revisiones.** Asentar las revisiones de 2.3, 2.4, 4.2 y 5.4
   sin review; resolver la atribución de 2.10 (la plantilla la creó P1); decidir
   si la revisión de 2.5 por P4 se documenta fuera de GitHub.
3. **Verificación técnica.** Reconciliar 174/176/178/184 con
   `pytest --collect-only` y correr la suite completa; revisar las dos pruebas de
   fecha con `date.today()`; definir la idempotencia de `terminar`; decidir el
   404 de `vinos-sin-stock`, el filtro `q` por documento y el mapeo de `22007`;
   ejecutar S1–S12 y D1–D6 sobre `full`; acotar o aceptar el
   `ALTER DEFAULT PRIVILEGES` de `reporte_ro`.
4. **Nube y cierre.** Desplegar API y front con HTTPS y verificar `GET /salud`;
   restaurar el backup en una base nueva de la nube; ejecutar la prueba de
   máquina limpia; preparar la defensa individual (9.6), el ensayo de
   modificaciones en vivo (9.7) y la lista de control final (9.8).

Riesgos: la inactividad de Aiven puede apagar el servicio antes de la demo; las pruebas dependientes de zona
horaria pueden fallar entre las 21:00 y las 00:00 ART; las mediciones de índices no son reproducibles en
magnitud; y varios entregables formales de la Fase 0 no existen aunque su contenido esté implementado.

### 9.4 Preparación de la defensa

`docs/guion_demo.md` (tarea 9.4, P2) propone una demo de 15 minutos: introducción, modelo, integridad
(RN-05/06/08/09/10/11/12/13), concurrencia, carga y rendimiento, consultas analíticas, seguridad y roles, y
cierre, con preguntas frecuentes sobre triggers, backups, `GENERATED ALWAYS`, volumen y por qué la lógica vive
en la base.

`docs/informe/revisiones-p3.md` deja preparada la parte de P3: qué revisó, qué no tiene review registrado y
qué discrepancias debe poder explicar (PR #5 de P2, tarea 2.10 de P1, despliegue de 8.5 de P4). Las tareas
9.6, 9.7 y 9.8 siguen **Pendientes**; no hay evidencia de su ejecución.

### 9.5 Cierre

El proyecto entrega un sistema completo y defendible: modelo relacional normalizado, integridad en la base,
carga masiva reproducible, índices con mediciones honestas, consultas analíticas, API REST sin lógica
duplicada, front que consume el contrato, despliegue en Aiven y documentación por tarea. Las mayores
fortalezas son la separación de responsabilidades entre base y API, la cobertura de pruebas de reglas y la
trazabilidad RN-01..RN-15. Las mayores deudas son formales —issue de stack, consultas al docente,
convenciones, revisiones y máquina limpia— y de verificación —cifra exacta de pruebas, ejecución completa de
consultas y HTTPS en la nube—. Ninguna de esas deudas invalida lo construido; todas deben quedar cerradas
antes de la defensa.
