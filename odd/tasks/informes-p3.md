# Feature: Informes de trabajo P3 (`docs/informe/`)

## Objetivo

Redactar en `docs/informe/` los informes faltantes de las tareas asignadas a P3
en el plan oficial del TPI «Bodegas del Atuel», con el estilo y nivel de detalle
de los informes existentes de P1/P2/P4, basados solo en evidencia verificable.

## Problema

Los informes existentes cubren la mayor parte de las tareas de P3 (Fase 6 y 5.3
en `07-api.md`), pero faltan informes de las tareas 0.4, 0.5, 1.7, 2.5, 6.11
(detalle del lado P3), 8.5 y 9.2, además del registro de la participación y las
revisiones de P3 sobre entregas de otros integrantes.

## Por qué

La definición de «hecho» del plan exige, por tarea, código + prueba + un
párrafo del informe en `docs/informe/NN-nombre.md` + PR aprobado. Sin informe,
la tarea no es defendible ante el docente aunque el trabajo exista.

## Scope autorizado

- Única superficie de escritura: los 8 archivos nuevos listados abajo dentro de
  `docs/informe/`.
- Prohibido modificar código, SQL, migraciones, tests, otros documentos o los
  informes existentes. Sin commits, push, PR ni merge.

## Tareas

| ID | Tarea plan | Estado auditado | Archivo de informe | Ruta |
|----|-----------|-----------------|--------------------|------|
| T1 | 0.4 Decidir el stack | Parcial: sin issue de decisión; README describe stack genérico (L16-22); framework concreto solo en `api/requirements.txt` | 00-4-decision-stack.md | `docs/informe/00-4-decision-stack.md` |
| T2 | 0.5 Consultas al docente | Pendiente: no existe `docs/decisiones.md` (entregable); sin evidencia de consultas enviadas | 00-5-consultas-docente.md | `docs/informe/00-5-consultas-docente.md` |
| T3 | 1.7 OpenAPI borrador y revisión de 001 | Hecho con salvedad: `api/openapi.yaml` creado en PR #2 (20 rutas, 34 esquemas); review de 001 (PR #1) APPROVED pero sin comentarios escritos | 01-7-openapi.md | `docs/informe/01-7-openapi.md` |
| T4 | 2.5 Vistas y roles | Hecho con diferencia: 4 vistas convencionales (plan pedía 3, una podía ser materializada); 3 roles con privilegios mínimos; PRs #2, #13, #15, #22 | 02-5-vistas-roles.md | `docs/informe/02-5-vistas-roles.md` |
| T5 | 6.11 Pruebas automáticas (detalle P3) | Hecho: suite amplia (≥8 y ≥3 violaciones de regla superadas); CI cerrado por P4 (PR #31); discrepancia de cifras 174 vs 176 vs 184 a reconciliar | 06-11-tests-api.md | `docs/informe/06-11-tests-api.md` |
| T6 | 8.5 Despliegue de la API (apoyo P3) | Hecho (apoyo): variables de entorno documentadas (07-api.md L100-129) + `POSTGRES_SSLMODE`/Aiven (PR #40) | 08-5-despliegue-api.md | `docs/informe/08-5-despliegue-api.md` |
| T7 | 9.2 Informe final (estado/trazabilidad) | Hecho: estado y mapeo capítulo→fuentes; consolidado en T9 | 09-2-informe-final.md | `docs/informe/09-2-informe-final.md` |
| T8 | Revisiones y participación P3 (0.3, 1.3, 1.9, 2.3, 2.4, 2.10, 4.2, 5.4 + apoyo Fase 7) | Parcial: reviews de P3 registrados solo en PR #1, #3, #7 (el CHANGES_REQUESTED del PR #5 fue de P2, corregido tras verificación); tareas 2.3/2.4/4.2/5.4 sin review en GitHub; 2.10 (plantilla) la hizo P1; 0.3 sin evidencia | revisiones-p3.md | `docs/informe/revisiones-p3.md` |
| T9 | 9.2 Informe final consolidado (9 capítulos) | Hecho: 894 líneas, 9 capítulos (sección 10.2), resume los 29 informes de `docs/informe/` | informe-final.md | `docs/informe/informe-final.md` |
| T10 | README: completar nombres P1/P3/P4 | Hecho: P1 Alejo Basile, P3 Ivan Malaniuk, P4 Benjamin Diaz | README.md | `README.md` |
| T11 | PR sin mergear (commits + push + gh pr create) | Hecho: PR #44 abierto a main, sin mergear | — | rama `docs/informes-p3` |

## Evidencia de entrega (T9–T11)

- Rama: `docs/informes-p3` sobre `origin/main` (`3146b62`).
- `a8bb4b9` — `docs(informe): agrega informes de tareas P3 e informe final consolidado (9.2)` (10 archivos, 2140 inserciones).
- `ef4b3cd` — `docs(readme): completa nombres de P1, P3 y P4` (3 inserciones, 3 borrados).
- PR: https://github.com/BenjaDiaZzZ/Bodegas-del-atuel/pull/44 — **abierto, sin mergear** (decisión del usuario).

## Cobertura ya existente (NO duplicar)

- 5.3 y 6.1–6.10, 6.12, 6.13: `docs/informe/07-api.md` (P3).
- Revisión de 6.11/6.13 desde P4: `docs/informe/06-13-compose-ci.md`.

## Criterios de aceptación

1. Cada informe sigue el estilo de `02-8-runner-tests.md` / `06-13-compose-ci.md`:
   título con ID de tarea, metadatos (Responsable/Dependencias), Objetivo,
   desarrollo con evidencia (PRs, commits, archivos, comandos con resultados),
   Verificación y Pendientes/observaciones.
2. Toda afirmación de trabajo realizado cita evidencia concreta verificable;
   donde no la hay se declara «sin evidencia» o «pendiente».
3. Sin datos inventados: fechas, hashes, cifras de tests y resultados solo si
   aparecen en la evidencia de la auditoría.
4. Español profesional neutro (sin voseo ni jerga), al estilo de los informes
   existentes.
5. Ningún archivo fuera de los 8 listados se modifica.

## Verificación

- Readback estructural de los 8 archivos (encabezados, secciones esperadas).
- Spot check: al menos 2 referencias a PR/commit verificadas con `gh`/`git`.
- `git status --short` confirma que solo cambian los 8 archivos de
  `docs/informe/` (más los artefactos `odd/` de tracking).

## Riesgos / notas

- 2.10 contradice el plan: la plantilla de `docs/trazabilidad.md` fue creada
  por P1 (commit `3dc623ca`), no por P3.
- Reviews asignados a P3 (2.3, 2.4, 4.2, 5.4) sin registro en GitHub: se
  documentan como «no verificables», no como hechos.
- El usuario prohibió commits: sin work-unit commits ni review lifecycle nativo
  (edición pasiva documental → structural readback).

## Progreso

- [x] Auditoría plan + informes existentes + Git/PRs (delegado a exploradores)
- [x] Matriz tarea→estado→evidencia→archivo
- [x] T1..T8 informes redactados (writer delegado; 8 archivos, 1116 líneas totales)
- [x] Readback estructural y spot check (git status limpio; PR #5 = review de P2 confirmado con gh; front sin React confirmado)
- [x] Resumen final al usuario

## Correcciones de evidencia (post-writer)

- Front real: JavaScript modular + Vite (no React como recomendaba el plan) — `front/package.json` solo declara `vite`.
- Review CHANGES_REQUESTED del PR #5: autor MaJuVer (P2), no ivann-02 (P3).
- Conteo de pruebas `def test_`: 184 (secuencia documentada 174 → 176 → 178 → 184).
- `08-nube.md` L157 atribuye el despliegue de la API a P3; el plan lo asigna a P4 con apoyo de P3 (discrepancia a corregir por P4).
- `origin/main` local (a43e63b) no contiene el merge del PR #40 aunque GitHub lo muestra mergeado.
