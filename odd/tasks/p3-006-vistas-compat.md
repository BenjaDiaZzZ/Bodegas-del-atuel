# Feature: p3-006-vistas-compat

## Objetivo

Verificar la compatibilidad de `db/migrations/006_vistas.sql` contra las
migraciones 001–005 (trabajo de P1/P2 ya integrado en `main`) y, solo donde
exista divergencia demostrada o incoherencia con el contrato, adaptar las
vistas. Cerrar con pruebas ejecutadas.

## Problema

`006_vistas.sql` se escribió (PR #2) antes de que se integraran 002–005. Su
encabezado afirma "Dependencias: 001_esquema.sql. No dependen de 002 a 005",
pero esa afirmación nunca se verificó contra las funciones contratadas
(`fn_stock_sala`, `fn_total_comprobante`), los triggers que mantienen totales
y stock (RN-08/RN-09) y los constraints de 002. Las vistas son insumo de la
API (Fase 6, plan 6.10) y deben devolver los mismos resultados que las
funciones de la base.

## Por qué importa

- Criterio 2.5 del plan (vistas y roles, P3) y coherencia con `docs/contratos.md`.
- La API (6.10) expondrá estos reportes: si la vista y la función divergen,
  la API queda en el medio.
- Defensa individual: hay que poder explicar por qué las vistas usan (o no)
  las funciones y los totales mantenidos por triggers.

## Fuente de verdad

- `db/migrations/001_esquema.sql` … `005_triggers.sql` (rama actual = `main`).
- `docs/contratos.md` (firmas `fn_*`/`sp_*`, formato de errores).
- Plan 2.5 y 6.10; TPI Anexo A.4 (`fn_stock_sala` STABLE), A.5 (carrera de stock), A.6.
- Auditoría previa (hallazgos F1–F20 del informe 2026-11-07): relevan F2
  (descuento efectivo) y el mantenimiento de totales por trigger.

## Alcance autorizado (edit surfaces)

- `db/migrations/006_vistas.sql`
- `db/tests/test_006_vistas.sql` (nuevo, autorizado)

Nada más. Ante un fix que pertenezca a archivos de P1/P2 (002–005,
`db_tests.sql`), reportar sin editar.

## Tareas

| ID | Tarea | Ruta | Estado |
|----|-------|------|--------|
| T1 | Análisis de compatibilidad estructural y semántica 006 vs 001–005 | delegado (writer) | completa |
| T2 | Tests de vistas (`test_006_vistas.sql`): sembrar vía triggers, comparar vistas vs `fn_*` | delegado (writer) | completa |
| T3 | Adaptar 006 solo con divergencia demostrada; documentar decisión en el encabezado | delegado (writer) | completa (solo encabezado: sin divergencia en las definiciones) |
| T4 | Verificación: PostgreSQL 16 efímero, 001→007, tests + regresión `db_tests.sql` | writer (foreground) + spot check del padre | completa (evidencia abajo) |
| T5 | Cierre: decisiones, gate de revisión RDD, sugerencia de commit/PR (sin ejecutar) | padre | completa (revisión aprobada y quemada; commit pendiente de autorización) |

## Criterios de aceptación

1. Las migraciones 001→007 aplican limpio sobre una base vacía (PostgreSQL 16).
2. Las 4 vistas responden y sus resultados coinciden con `fn_stock_sala` /
   `fn_total_comprobante` / `comprobante.total` donde el contrato dice que la
   base es la que calcula.
3. `test_006_vistas.sql` pasa, o queda documentado el ciclo RED→GREEN.
4. `db/tests/db_tests.sql` sigue pasando (regresión de las reglas RN).
5. Ningún archivo fuera de las edit surfaces se modifica; no se hace commit.

## Riesgos y trampas conocidas

- El constraint trigger diferido de RN-05 no salta en transacciones con
  ROLLBACK; para validarlo dentro de un test usar `SET CONSTRAINTS ALL IMMEDIATE`.
- No ejecutar `scripts/reset_db.sh` ni tocar la base de desarrollo: usar
  siempre un contenedor Docker efímero (`--rm`).
- Usar `CREATE OR REPLACE VIEW` para preservar los ACL de 007.
- No inventar resultados: todo check se reporta como `<comando>: <resultado observado>`.

## Verificación (resultados observados, 2026-11-07)

| Comando | Resultado observado |
|---|---|
| Migraciones 001→007 en PostgreSQL 16 efímero (`docker run --rm`) | 7/7 OK, sin errores |
| `psql -v ON_ERROR_STOP=1 < db/tests/test_006_vistas.sql` | exit=0; A1–A5 OK; ROLLBACK sin residuos |
| `psql -v ON_ERROR_STOP=1 < db/tests/db_tests.sql` | exit=0; 65 NOTICE OK; 0 errores |
| Reaplicar 006 después de 007 (ACL) | exit=0; `app_rw`/`reporte_ro` conservan SELECT |
| Spot check del padre (misma secuencia) | exit=0; idéntico al reporte del writer |
| Run negativo (base con una fila previa 9001) | exit=3; mensaje claro "la base no está limpia" (prueba de R3-001) |

Sin RED previo dentro del stack: A1–A5 pasan contra el 006 original (prueba de
regresión; excepción TDD documentada). Contrafáctico observado que demuestra la
dependencia semántica: sin 005, `vw_ventas_mensuales_sala` informa 0.00 y
`fn_total_comprobante` informa 2700.00.

## Revisión RDD (gate de verificación delegada)

- Modo RDD: on (global). Riesgo nativo: `medium` (executable_change en 006).
  Lente seleccionado: `review-reliability` (orden 0). Presupuesto de corrección: 200 líneas (sin uso).
- Candidato congelado: lineage `review-ace485221aa8b986`, 3 archivos, 598 líneas.
- Resultado: **aprobado** en el último evento admitido; acknowledgement exacto
  ejecutado tras STATUS restart → `gentle-ai.review-acknowledged/v1`,
  `authority: burned`.
- Hallazgos del revisor (todos `SUGGESTION`, no bloqueantes, sin corrección):
  - **R3-001** (`db/tests/test_006_vistas.sql:31`): los IDs fijos 9001+ asumen
    base limpia sin verificarlo. **Aplicada:** precondición verificada en
    runtime antes de sembrar; el run negativo observado devuelve exit=3 con
    mensaje claro.
  - **R3-002** (`db/tests/test_006_vistas.sql:311-324`): A3 solo cruzaba
    `fn_total_comprobante` para el comprobante 9001 (marzo). **Aplicada:**
    cross-check de abril contra `fn_total_comprobante(9002)` y
    `comprobante.total`.
  - **R3-003** (`odd/tasks/p3-006-vistas-compat.md:51`): el tablero marcaba T4
    pendiente mientras el encabezado de 006 afirmaba la verificación.
    **Resuelto** en esta actualización.

## Progreso

- 2026-11-07: feature creada; rama `feature/p3-006-vistas-compat` sobre `main` (4c7ccfe). Skill `caveman` instalada (no activa).
- 2026-11-07: T1–T3 completadas por writer delegado. Veredicto: las 4 vistas
  son estructural y semánticamente compatibles con 001–005; se corrigió solo el
  encabezado de dependencias (+13/−1) y se agregó `test_006_vistas.sql` (509 lín.).
- 2026-11-07: T4 completada — ver tabla de verificación; spot check del padre OK.
- 2026-11-07: T5 completada — revisión RDD aprobada y autoridad quemada
  (`review-ace485221aa8b986`). Pendiente solo la decisión de commit/PR del usuario.
- 2026-11-08: mejoras R3-001 y R3-002 del revisor aplicadas y verificadas
  (run positivo exit=0, regresión `db_tests` 65 OK, run negativo exit=3 con
  mensaje claro). Listo para el work-unit commit.
