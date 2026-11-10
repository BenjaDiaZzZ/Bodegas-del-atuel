# 1.7 · OpenAPI borrador y revisión de 001

**Responsable:** P3 (API)
**Depende de:** 0.3 (convenciones y contrato) y 1.3 (`001_esquema.sql`).
**Revisa:** P1 y P4 según la cadena del plan.

## Objetivo

Escribir `api/openapi.yaml` con los endpoints de la sección 6 del enunciado y
revisar `001_esquema.sql` preguntándose si falta algún dato que la API necesite.
El entregable tiene dos partes: el contrato y los comentarios en el PR de 001.
El criterio de «hecho» es que P1 haya resuelto las observaciones.

## Entregable 1 — `api/openapi.yaml`

El contrato se incorporó en el **PR #2** («feat(p3): agrega OpenAPI, borrados
D1-D6, vistas y roles»), mergeado el **2026-11-05 23:41:47 UTC** por MaJuVer.
El PR declara explícitamente las tareas «1.7 OpenAPI borrador · 2.5 Vistas y
roles · 5.3 Consultas DELETE (D1–D6)».

Datos verificables del archivo y del PR:

| Dato | Valor | Fuente |
|---|---|---|
| Especificación | OpenAPI 3.0.3 | `api/openapi.yaml` L1 |
| Rutas | 20 | `grep -c "^  /" api/openapi.yaml` |
| Esquemas | 34 | body del PR #2 |
| Líneas agregadas | 1552 | `gh pr view 2 --json files` |
| Driver declarado | psycopg 3, SQL parametrizado, sin ORM | `api/openapi.yaml` L10 |

El contrato cubre salud, vinos, clientes, comprobantes, transferencias,
ingresos y reportes. En la Fase 6 el archivo creció hasta **26 operaciones**
(25 del contrato inicial más `/salud`) y se cotejó contra las rutas reales de
la aplicación; ese trabajo se documenta en `docs/informe/07-api.md`, sección
«Tarea 6.13», y no se duplica aquí.

### Alcance del borrador

El propio archivo aclara que es la Fase 1.7 y que los endpoints de escritura se
completan en la Fase 6 (L18-19). Por eso el valor del entregable es el contrato
de rutas, esquemas y códigos de error, no la implementación.

## Entregable 2 — revisión de `001_esquema.sql`

El PR #1 («feat(db): esquema físico 001 con 29 tablas y 34 FK») fue mergeado el
**2026-11-05 16:20:08 UTC**. La revisión de P3 quedó registrada como
**APPROVED** el **2026-11-05 16:19:54 UTC**, con **cuerpo vacío**.

Eso significa que la aprobación existe, pero **no hay comentarios escritos** que
documenten observaciones sobre el esquema. La parte del entregable «comentarios
en el PR de 001» no tiene evidencia registrada.

### Salvedad sobre el criterio de «hecho»

El criterio «P1 resolvió las observaciones» no puede verificarse: no hay
observaciones escritas que P1 pudiera resolver. La aprobación sin cuerpo es
compatible con una revisión oral o fuera de GitHub, pero eso no deja evidencia
auditable.

Además, las observaciones que sí quedaron registradas en el repositorio son del
review de P2 sobre `002_constraints.sql` (PR #5) y se canalizaron en el issue
#6, no en una revisión de P3 sobre 001. El issue #6 documenta dos cambios
pendientes: PK natural `codigo_postal` en `localidad` y `vino.cod_vino` como
`GENERATED ALWAYS`. Es evidencia de que el esquema tuvo observaciones, pero no
de que P3 las haya formulado en el PR #1.

## Alineación posterior con las constraints

El contrato se redactó antes de que varias correcciones del esquema llegaran a
`main`. La sección «Tarea A» de `docs/informe/07-api.md` contrasta enums, rangos
y campos de los request schemas contra `db/migrations/002_constraints.sql` y
corrige las diferencias (por ejemplo `presentacion_ml`, `anada`,
`graduacion`, `porcentaje` y `direccion`). Esa sección es la referencia
cruzada para la alineación; este informe solo registra que la alineación
existió y quedó documentada.

## Verificación

```text
$ gh pr view 2 --json number,title,mergedAt
{"mergedAt":"2026-11-05T23:41:47Z","number":2,"title":"feat(p3): agrega OpenAPI, borrados D1-D6, vistas y roles"}

$ gh pr view 1 --json reviews   # extracto
[{"author":{"login":"ivann-02"},"body":"","state":"APPROVED",
  "submittedAt":"2026-11-05T16:19:54Z"}]

$ grep -c "^  /" api/openapi.yaml
20
```

## Estado

**Hecho con salvedad.** El entregable `api/openapi.yaml` existe, está aprobado
y se alineó después con las constraints. La revisión de 001 tiene aprobación
registrada, pero sin comentarios escritos; por eso el criterio «P1 resolvió las
observaciones» queda **no verificable**.

## Pendientes y observaciones

- **Pendiente:** si la revisión de 001 tuvo observaciones, dejarlas asentadas
  en el PR o en un issue, aunque sea a posteriori. Sin eso, la defensa de la
  tarea 1.7 se apoya solo en la aprobación.
- **No verificable:** el contenido de la revisión oral de 001. No hay evidencia
  en GitHub ni en el repositorio.
- **Observación:** el contrato inicial tenía 20 rutas y la implementación
  terminó con 26 operaciones. La diferencia está explicada en `07-api.md`; no
  es un error del borrador, sino la evolución prevista por la Fase 6.
