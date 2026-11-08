# p3-007-roles-minimos · Permisos explícitos por tabla en 007_roles.sql

- **Rama:** `feature/p3-007-roles-minimos` (desde `main`)
- **Solicitante:** P1 (Datos-Núcleo) — requisito de GRANT mínimos
- **Rol responsable:** P3
- **Estado:** en progreso

## Problema

`db/migrations/007_roles.sql` otorga privilegios con `ON ALL TABLES` (GRANT y
ALTER DEFAULT PRIVILEGES). Eso incumple el requisito de privilegios mínimos de
P1 y deja a `app_rw` con `UPDATE` y `DELETE` efectivos sobre
`renglon_comprobante`, cuyos triggers solo cubren `INSERT` (T1/T2 en
`005_triggers.sql`), por lo que una modificación directa desincroniza
`comprobante.total` sin que nada lo repare.

## Objetivo

Reemplazar todos los GRANT/REVOKE `ON ALL ...` por permisos explícitos objeto
por objeto, aplicando mínimo privilegio, y garantizar que `app_rw` no tenga
`UPDATE` ni `DELETE` efectivos sobre `renglon_comprobante`, con pruebas
automatizadas de privilegios efectivos que lo verifiquen.

## Requisito literal de P1

> "En 007_roles.sql (Para cumplir el requisito de GRANT mínimos): Tienen que
> dejar de usar ON ALL TABLES y otorgar permisos tabla por tabla. A app_rw no se
> le debe dar UPDATE ni DELETE sobre renglon_comprobante."

## Alcance autorizado

- `db/migrations/007_roles.sql` (reescritura de las secciones de privilegios)
- `db/tests/test_007_roles.sql` (archivo nuevo)

Nada más. No tocar migraciones 001–006, `api/`, `consultas/`, `scripts/` ni
documentación compartida. La guía de estudio personal (`../guiaEstudioBDD.md`)
se actualiza aparte, al cierre.

## Decisiones aprobadas

1. Ningún GRANT/REVOKE usa `ON ALL TABLES/SEQUENCES/ROUTINES`: listas
   explícitas de objetos en todas las sentencias (incluidos los REVOKE a
   PUBLIC, para que la literalidad del requisito sea verificable por grep).
2. `app_rw` sobre `renglon_comprobante`: **solo INSERT** (+ SELECT). Ni UPDATE
   ni DELETE. Protege `comprobante.total`.
3. `renglon_ingreso` y `renglon_transferencia`: solo INSERT salvo evidencia
   empírica de que los `SELECT ... FOR UPDATE` de `sp_procesar_*` exigen
   UPDATE (ver chequeo empírico abajo).
4. `reporte_ro`: solo SELECT explícito (tablas y vistas).
5. `bda_owner`: privilegios completos explícitos por objeto.
6. `ALTER DEFAULT PRIVILEGES`: sin escritura implícita para objetos futuros
   (como mucho SELECT); las tablas nuevas escribibles requieren GRANT explícito.
7. Los `REVOKE ... FROM PUBLIC` se conservan (revocan, no otorgan) pero
   explícitos por objeto.

## Matriz de app_rw — método de derivación

Privilegio de escritura por tabla = unión de:
(a) DML implícito en cada operación OpenAPI de escritura (mapear operationId →
    tablas, incluidas colecciones hijas sincronizadas: `composicion`,
    `vino_maridaje`, `socio`, `distribuidor`, `exportador`);
(b) DML ejecutado por funciones trigger (`SECURITY INVOKER`, corren como
    `app_rw`): T2 actualiza `comprobante` y `stock_sala`;
    `fn_tg_vino_precio_auditoria` inserta en `auditoria_precio`;
(c) DML dentro de `sp_procesar_ingreso` / `sp_procesar_transferencia`:
    UPDATE `ingreso`/`transferencia`, UPDATE/INSERT `stock_deposito`/`stock_sala`.
La tabla-resultado queda documentada como comentario de auditoría en
`007_roles.sql` (sentencia → tablas → por qué).

Celdas ya verificadas por el padre (no remover):
- INSERT: vino, cliente, composicion, vino_maridaje, socio, distribuidor,
  exportador, comprobante, renglon_comprobante, ingreso, renglon_ingreso,
  transferencia, renglon_transferencia, stock_deposito, stock_sala,
  auditoria_precio.
- UPDATE: vino, cliente, comprobante, stock_sala, stock_deposito, ingreso,
  transferencia (+ colecciones hijas si el contrato las sincroniza).
- DELETE: vino, cliente (+ colecciones hijas si el contrato las sincroniza).
- SELECT: todas las tablas y vistas (triggers y reportes leen amplio).

## Chequeo empírico obligatorio

En PostgreSQL 16, ¿`SELECT ... FOR UPDATE` exige privilegio UPDATE? Probar
como `reporte_ro` sobre `renglon_transferencia` y documentar el resultado
observado. Si exige UPDATE, `app_rw` necesita UPDATE sobre
`renglon_ingreso`/`renglon_transferencia` (los locks de `sp_procesar_*`);
concederlo y documentar. Sobre `renglon_comprobante` la prohibición es total
(requisito de P1), sin excepciones.

**Resultado observado (PG 16.15, sonda del padre con rol solo SELECT):**
`SELECT ... FOR UPDATE` devuelve `42501 permission denied` tanto con filas
como sobre tabla vacía: el privilegio se valida al iniciar la ejecución, no
por fila. Decisión 3 aplicada: `app_rw` recibe UPDATE —nunca DELETE— sobre
`renglon_ingreso` y `renglon_transferencia`. Segundo hallazgo confirmado:
`ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON ROUTINES FROM PUBLIC` es
no-op en PG16 (la función nueva queda con `EXECUTE` implícito de PUBLIC), y
la combinación GRANT+REVOKE como default tampoco lo elimina: el control
efectivo de rutinas futuras es el REVOKE por objeto en cada migración, tal
como documenta la sección 8 de `007_roles.sql`.

## Tareas

- [x] T1 — Rama `feature/p3-007-roles-minimos` desde `main` + este documento.
- [x] T2 — `db/tests/test_007_roles.sql` (RED primero) con matriz de
      privilegios efectivos, denegaciones vivas, sonda PUBLIC, default ACLs,
      memberships y smoke del camino de venta/procesamiento como `app_rw`.
- [x] T3 — Reescritura de `db/migrations/007_roles.sql` con grants
      explícitos según la matriz (GREEN).
- [x] T4 — Suite completa sin regresiones: `db_tests.sql` OK,
      `test_007_roles.sql` OK, `grep -c "ON ALL"` = 0. `test_006_vistas.sql`
      OK ejecutado desde el contenido de la rama `feature/p3-006-vistas-compat`
      (aún sin mergear en esta rama; se verificó compatibilidad cruzada).
- [ ] T5 — Commit de trabajo (Conventional Commit) + cierre de este documento.

## Criterios de aceptación

1. `007_roles.sql` no contiene `ON ALL` en ninguna sentencia GRANT/REVOKE.
2. `has_table_privilege('app_rw','renglon_comprobante','UPDATE'/'DELETE')` es
   falso; un intento real devuelve `42501`.
3. Cada sentencia de privilegio tiene justificación documentada.
4. Privilegios efectivos de los tres roles verificados en ambos sentidos
   (lo concedido otorga, lo vedado deniega).
5. Sin fugas por PUBLIC, memberships ni default ACLs.
6. `db_tests.sql` y `test_006_vistas.sql` pasan sin regresiones.
7. El camino de venta como `app_rw` (INSERT comprobante + renglones,
   recálculo de total por T2) funciona con los nuevos permisos.

## Verificación aplicable

```
./scripts/reset_db.sh
psql ... -v ON_ERROR_STOP=1 -f db/tests/db_tests.sql
psql ... -v ON_ERROR_STOP=1 -f db/tests/test_006_vistas.sql
psql ... -v ON_ERROR_STOP=1 -f db/tests/test_007_roles.sql
```

TDD aplicable: runner `psql` contra el contenedor Docker (PostgreSQL 16,
migraciones 001→007). RED observado antes de tocar `007_roles.sql`; GREEN
después; regresión completa al cierre.

## Rutas y delegación

- T2–T3: **delegado** (writer único). Disparador: 2+ archivos no triviales.
- T4: correr por el writer como verificación del alcance; spot check del padre.

## Estrategia de entrega

- **single-pr** (una unidad de trabajo: fix + sus pruebas son inseparables).
- Forecast: ~550 líneas autoradas (matriz explícita + suite de privilegios).
  Supera el heurístico de ~400 por la verbosidad mecánica de listar 29 tablas
  y por la matriz de aserciones; no se parte en PRs encadenados porque separar
  el fix de su prueba rompe la revisabilidad de la unidad.

## Progreso y evidencia

- T1 completado: rama creada desde `main`, `.env` local generado desde
  `.env.example` (gitignored).
- T2–T3 completados por writer delegado (runtime `general`; el worker por
  defecto quedó bloqueado por política de región del modelo). Se corrigió un
  dato falso del encabezado de `007_roles.sql` en el spot check del padre:
  el check de privilegios de `FOR UPDATE` no es dependiente de filas.
- Evidencia de verificación (comando: resultado observado):
  - `./scripts/reset_db.sh`: OK (PG 16.15, migraciones 001→007).
  - `psql -f db/tests/test_007_roles.sql` contra la 007 previa: **RED**
    (`FAIL: rol app_rw PRIV INSERT en vw_stock_total_vino: esperado
    retenido, observado concedido`).
  - `psql -f db/tests/test_007_roles.sql` post-cambio y tras spot check del
    padre: **GREEN** (secciones A–F; denegaciones 42501 de
    `renglon_comprobante`, humo de venta con recálculo de total, CALL
    `sp_procesar_*` como `app_rw`, auditoría de precio).
  - `psql -f db/tests/db_tests.sql`: OK (RN-01..RN-15, 0 FAIL).
  - `psql -f db/tests/test_006_vistas.sql`: OK (compatibilidad cruzada).
  - `grep -c "ON ALL" db/migrations/007_roles.sql`: 0.
- Matriz final de `app_rw`: INSERT sobre las 17 tablas de escritura de la
  matriz (incluye `renglon_comprobante`); UPDATE sobre vino, cliente,
  comprobante, stock_sala, stock_deposito, ingreso, transferencia,
  renglon_ingreso, renglon_transferencia, distribuidor, exportador; DELETE
  sobre vino, cliente, composicion, vino_maridaje, permiso_exportacion;
  SELECT sobre las 29 tablas y 4 vistas; USAGE sobre 6 secuencias identity;
  EXECUTE sobre las 6 rutinas contratadas. Sin UPDATE/DELETE de
  `renglon_comprobante`.
- Siguiente: T5 (commit de trabajo + cierre).
