# 2.5 · Vistas y roles

**Responsable:** P3 (API)
**Revisa:** P4 (Front e Infraestructura)
**Dependencias:** 2.1 (`002_constraints.sql`), 2.2 (`003_funciones.sql`),
2.3 (`004_procedimientos.sql`) y 2.4 (`005_triggers.sql`).

## Objetivo

Entregar las vistas de reporte y la matriz de roles de la aplicación. El plan
pide `006_vistas.sql` con tres vistas —stock total por vino, ventas mensuales
por sala y documentos pendientes—, pudiendo una ser materializada, y
`007_roles.sql` con tres roles: propietario, `app_rw` (lectura y escritura de
la API) y `reporte_ro` (solo lectura). Las contraseñas no deben quedar en el
repositorio. El criterio de «hecho» es que `app_rw` pueda operar pero no crear
ni borrar tablas, y que `reporte_ro` no pueda escribir.

## Entregable 1 — `db/migrations/006_vistas.sql`

El archivo tiene **219 líneas** y define **cuatro vistas convencionales**. El
encabezado (L4-16) explica la diferencia con el plan: el mínimo era tres vistas
y una podía ser materializada; se implementaron cuatro y ninguna es
materializada.

| Vista | Líneas | Propósito |
|---|---|---|
| `vw_stock_total_vino` | L41-68 | Stock por vino sumando depósito y salas. |
| `vw_ventas_mensuales_sala` | L90-125 | Ventas agrupadas por sala y mes. |
| `vw_documentos_pendientes` | L138-165 | Ingresos y transferencias no procesados. |
| `vw_ficha_vino` | L177-214 | Ficha completa para S9 y para el detalle de vino de la API. |

### Por qué no se usó una vista materializada

El encabezado (L12-16) justifica la decisión: el stock y las ventas cambian con
cada operación y el volumen del TPI no justifica el costo de mantenimiento de
un `REFRESH MATERIALIZED VIEW`. Deja abierta la posibilidad de convertir
`vw_stock_total_vino` en materializada si las mediciones de la Fase 4 muestran
que el reporte es costoso.

### Diferencia con el plan

El plan pedía tres vistas; se entregaron cuatro. La cuarta, `vw_ficha_vino`,
no es un adorno: soporta la consulta S9 y el detalle de vino que consume la
API. La diferencia está documentada en el propio archivo y en el body del
PR #2, por lo que es una desviación conocida, no un faltante.

## Entregable 2 — `db/migrations/007_roles.sql`

El archivo tiene **464 líneas**. Crea los tres roles con `NOLOGIN` (L103-118) y
deja las contraseñas fuera del repositorio: `scripts/set_role_passwords.sh` las
toma de `DB_PASSWORD` y `REPORTE_RO_PASSWORD` del entorno.

| Rol | Propósito | Privilegios principales |
|---|---|---|
| `bda_owner` | Propietario lógico de la base y los objetos | `CREATE` sobre el esquema `public` (L139-140); privilegios completos por objeto. |
| `app_rw` | Rol de la API | `SELECT`, `INSERT`, `UPDATE` y `DELETE` mínimos por tabla y por columna (L274-370); sin DDL; sin `USAGE` sobre secuencias (L354). |
| `reporte_ro` | Rol de reportes | Solo `SELECT` sobre las cuatro vistas y seis tablas justificadas (L381-396). |

### Cierre de privilegios públicos

El archivo revoca privilegios a `PUBLIC` en el esquema, las tablas, las vistas,
las secuencias, las rutinas y la base (L138, 193-200, 203-205, 208-214,
220-228 y 456). El `GRANT CREATE` sobre el esquema queda solo para
`bda_owner` (L139-140); `app_rw` y `reporte_ro` reciben únicamente `USAGE`.

La matriz de `app_rw` no usa `ON ALL TABLES`: cada `GRANT` enumera objetos
explícitos y documenta qué operación de `api/openapi.yaml`, trigger de 005 o
procedimiento de 004 lo justifica. En particular, `app_rw` no tiene `UPDATE` ni
`DELETE` sobre `renglon_comprobante`, y no tiene `USAGE` sobre las secuencias
identity.

### Riesgo residual documentado

`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO
reporte_ro` (L448-449) concede `SELECT` sobre toda tabla futura a `reporte_ro`.
El archivo lo declara como conveniencia deliberada y riesgo residual: una tabla
sensible nueva quedaría legible sin un `REVOKE` explícito. Quitar o acotar ese
default es una decisión del equipo, no de esta migración.

## Pruebas y cierre

### PR #13 — pruebas de compatibilidad de vistas

«test(db): agrega pruebas de vistas 006 y aclara dependencias», mergeado el
**2026-11-08 20:15:50 UTC** (commit de merge `a5369c02`). Agregó
`db/tests/test_006_vistas.sql` (555 líneas en esa versión) y corrigió el
encabezado de `006_vistas.sql` para documentar la dependencia semántica real
con 002–005. Las aserciones A1–A5 comparan cada vista contra las funciones
contratadas y contra literales calculados a mano, para que la prueba no sea
tautológica.

### PR #15 — privilegios mínimos por objeto

«fix(db): privilegios mínimos por objeto en 007_roles.sql (requisito P1)»,
mergeado el **2026-11-08 20:16:13 UTC** (commit de merge `ad16e614`). Reemplazó
`ON ALL TABLES` por `GRANT`/`REVOKE` explícitos y agregó
`db/tests/test_007_roles.sql` con la matriz bidireccional de privilegios,
denegaciones vivas con SQLSTATE `42501`, control de fugas por `PUBLIC` y humo
del camino de venta como `app_rw`.

### PR #22 — cierre de auditoría

«fix(db): cierra auditoría final de permisos y vistas de P3», mergeado el
**2026-11-09 00:09:27 UTC** (commit de merge `c3b0422a`). Corrigió, entre otros:

- **R-015:** cast explícito `::timestamp` en el bucket mensual de
  `vw_ventas_mensuales_sala` para que no dependa del `TimeZone` de la sesión.
- **R-001/R-005:** `INSERT` y `UPDATE` por columna en documentos y renglones;
  `stock_sala`, `stock_deposito` y `auditoria_precio` quedaron en solo
  `SELECT`.
- **R-011:** `reporte_ro` pasó de 29 tablas a las 4 vistas más 6 tablas
  justificadas contra los endpoints de reportes.
- **R-012:** `UPDATE(cantidad)` en renglones de ingreso y transferencia.
- **R-013:** revocación de `USAGE` de las 13 secuencias a `app_rw`.
- **T9:** incorporación de `fn_tg_renglon_venta_inmutable` a las listas de
  rutinas, para que no quedara ejecutable por `PUBLIC`.

Resultados documentados en el body del PR #22, sobre PostgreSQL 16.15:

| Comprobación | Resultado |
|---|---|
| Migraciones 001–007 con `ON_ERROR_STOP` | 7/7 `exit=0`, 0 errores |
| `db/tests/test_006_vistas.sql` | 8 OK / 0 errores |
| `db/tests/test_007_roles.sql` | 38 OK / 0 errores |
| `db/tests/db_tests.sql` | 94 OK / 0 errores |
| `db_tests.sql` de `main` contra estas migraciones | 97 OK / 0 errores |
| Reaplicar 007 dos veces y 006 después | `exit=0`; ACL idéntica |

Los archivos actuales crecieron después de esos PR: `test_006_vistas.sql` tiene
688 líneas (incluye A0 y A6) y `test_007_roles.sql` tiene 1352 líneas (incluye
las secciones G–L). Los resultados de la tabla son los documentados en el PR
#22; **no se re-ejecutaron en esta sesión** porque no hay una base PostgreSQL
levantada para este informe.

## Verificación

```text
$ wc -l db/migrations/006_vistas.sql db/migrations/007_roles.sql
219 db/migrations/006_vistas.sql
464 db/migrations/007_roles.sql

$ grep -n "CREATE OR REPLACE VIEW" db/migrations/006_vistas.sql
41:CREATE OR REPLACE VIEW vw_stock_total_vino AS
90:CREATE OR REPLACE VIEW vw_ventas_mensuales_sala AS
138:CREATE OR REPLACE VIEW vw_documentos_pendientes AS
177:CREATE OR REPLACE VIEW vw_ficha_vino AS

$ grep -n "CREATE ROLE" db/migrations/007_roles.sql
103:        CREATE ROLE bda_owner NOLOGIN;
113:        CREATE ROLE app_rw NOLOGIN;
117:        CREATE ROLE reporte_ro NOLOGIN;

$ gh pr view 13 --json number,title,mergedAt   # extracto
{"mergedAt":"2026-11-08T20:15:50Z","number":13,...}
```

## Estado

**Hecho, con diferencia documentada.** Las cuatro vistas y los tres roles
existen, los privilegios mínimos están implementados y las pruebas cubren el
criterio de «hecho»:

- `app_rw` puede operar pero no crear ni borrar tablas: se verifica en las
  secciones B, G y H de `test_007_roles.sql` (denegaciones `42501` y columnas
  permitidas).
- `reporte_ro` no puede escribir: se verifica en las secciones C y J (solo lee
  las vistas y las tablas habilitadas).

La diferencia con el plan es que se entregaron cuatro vistas convencionales en
lugar de tres, y ninguna es materializada. La justificación está en el
encabezado de `006_vistas.sql`.

## Pendientes y observaciones

- **Revisión de P4:** el plan asigna la revisión de 2.5 a P4. No hay review
  registrado de P4 sobre el PR #2 en GitHub; la aprobación del PR #2 es de
  MaJuVer (P2). Conviene dejar asentada la revisión de P4 o documentar que se
  hizo fuera de GitHub.
- **Riesgo residual:** el `ALTER DEFAULT PRIVILEGES` de `reporte_ro` sobre
  tablas futuras sigue abierto como decisión de equipo.
- **No verificable en esta sesión:** los resultados 8/38/94/97 OK no se
  re-ejecutaron; se citan del body del PR #22. Para la defensa conviene correr
  `./scripts/run_db_tests.sh --reset` y conservar la salida.
- **Observación:** la cuarta vista no estaba pedida, pero soporta S9 y el
  detalle de vino de la API. No se propone eliminarla.
