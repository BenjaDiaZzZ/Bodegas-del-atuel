# Revisiones y participación de P3

**Responsable:** P3 (API)
**Alcance:** tareas de revisión asignadas a P3 en el plan y apoyo en la Fase 7.

## Propósito

Registrar la participación de P3 como revisor según la cadena del plan
(P1 → P2 → P3 → P4 → P1) y separar con precisión dos cosas distintas:

- **Review registrado en GitHub:** existe un evento de revisión con autor,
  estado y fecha.
- **Sin review registrado:** no hay evento, aunque la tarea se haya conversado
  o revisado por otro canal.

La distinción importa porque el plan exige revisiones registradas, y una
aprobación sin cuerpo o una revisión oral no dejan la misma evidencia.

## Resumen de tareas de revisión

| Tarea | Artefacto / PR | Estado | Evidencia |
|---|---|---|---|
| 0.3 Revisar convenciones y contrato de P1 | `docs/contratos.md` | Sin evidencia registrada | No hay review ni comentario de P3. `docs/convenciones.md` no existe. |
| 1.3 Revisar `001_esquema.sql` | PR #1 | Review registrado | APPROVED de ivann-02, 2026-11-05 16:19:54 UTC, sin cuerpo. |
| 1.9 Revisión cruzada y cierre de H1 | PR #1 | Review registrado | Misma aprobación que 1.3. |
| 2.3 Revisar `004_procedimientos.sql` | PR #10 | Sin review registrado | Array de reviews vacío. |
| 2.4 Revisar `005_triggers.sql` | PR #11 | Sin review registrado | Array de reviews vacío. |
| 2.10 Plantilla de trazabilidad | `docs/trazabilidad.md` | Contradicción con el plan | Creada por P1 en `3dc623ca` y completada en `7f1398ea` / PR #17. |
| 4.2 Revisar `008_indices.sql` | PR #23 | Sin review registrado | Array de reviews vacío. |
| 5.4 Revisar `select.sql` parte 1 | PR #24 | Sin review registrado | Array de reviews vacío. |
| Cadena de revisión de PRs de P2 | #3, #4, #7, #20, #21, #23, #24, #25, #38 | Parcial | P3 registró review solo en #3 y #7. |

## Reviews registrados

### PR #1 — `001_esquema.sql` (tareas 1.3 y 1.9)

- Autor del PR: Alejo-Basile (P1).
- Review de ivann-02: **APPROVED**, 2026-11-05 16:19:54 UTC.
- Cuerpo: vacío.
- Merge: 2026-11-05 16:20:08 UTC, por ivann-02.

La aprobación existe, pero no hay observaciones escritas. Para 1.9, la
revisión cruzada de H1 queda cubierta formalmente por esa aprobación; no hay
evidencia de observaciones que P1 haya tenido que resolver.

### PR #3 — normalización 3FN y diccionario (1.5 y 1.6)

- Autor del PR: MaJuVer (P2).
- Review de ivann-02: **APPROVED**, 2026-11-05 21:10:19 UTC.
- Cuerpo: vacío.

### PR #7 — catálogos del Anexo B (1.4)

- Autor del PR: MaJuVer (P2).
- Review de ivann-02: **APPROVED**, 2026-11-07 07:38:07 UTC.
- Cuerpo: vacío.

## Reviews no registrados

No hay review de ivann-02 en los PR #9, #10, #11, #12, #14, #16, #17, #20,
#21, #23, #24, #25 ni #26–#39. En particular, las tareas 2.3 (PR #10), 2.4
(PR #11), 4.2 (PR #23) y 5.4 (PR #24) quedan **sin review registrado**.

La cadena de revisión de P2 incluía los PR #3, #4, #7, #20, #21, #23, #24,
#25 y #38. P3 registró review solo en #3 y #7. Los demás se mergearon sin
review de P3.

## Discrepancia sobre el PR #5

Una nota previa de auditoría atribuía a P3 un review **CHANGES_REQUESTED** en
el PR #5 (`002_constraints.sql`) con cuatro bloqueantes y tres observaciones.
La verificación en GitHub muestra que ese review fue escrito por **MaJuVer
(P2)**, no por ivann-02 (P3). El cuerpo del review empieza con «Revisión P2 —
Solicito cambios» y enumera los cuatro bloqueantes:

1. `localidad` seguía usando `id_localidad` como PK en lugar de
   `codigo_postal`.
2. `vino.cod_vino` no era `GENERATED ALWAYS`.
3. `ck_renglon_comprobante_descuento` trataba el descuento como porcentaje.
4. Faltaban pruebas e informe de la tarea 2.1.

Por lo tanto, **P3 no revisó el PR #5**. El review es de P2 y debe citarse
como tal. Esta corrección es importante para no atribuir a P3 una revisión que
no hizo.

## Tarea 2.10 — plantilla de trazabilidad

El plan asigna a P3 la plantilla de la tabla de trazabilidad. La evidencia
muestra otra cosa:

- `docs/trazabilidad.md` fue creado por Alejo-Basile (P1) en el commit
  `3dc623ca` («feat(db): add 005 triggers for RN-05/08-13 y trazabilidad»).
- Se completó en el commit `7f1398ea` y en el PR #17
  («docs(trazabilidad): complete RN-01..RN-15 rows»), también de P1.

No hay evidencia de que P3 haya creado la plantilla. Es una **contradicción con
el plan** que conviene aclarar con el equipo: o se reasigna la tarea a P1, o se
documenta que P3 la revisó sin crearla.

## Tarea 0.3 — convenciones y contrato

No hay review registrado de P3. Además, `docs/convenciones.md` no existe: el
repositorio solo tiene `docs/contratos.md`. Eso es un entregable faltante de
P1 para la tarea 0.3, no una omisión de P3. Se menciona como observación para
que el equipo decida si el contrato existente alcanza o si falta el archivo de
convenciones.

## Fase 7 — apoyo a la integración del front

P3 no escribió los informes de front 7.1–7.7; esos son de P4. El apoyo de P3
fue habilitar la integración entregando la API real:

- **PR #30** («feat(api): Fase 6 completa — API REST con 26 endpoints reales
  sobre PostgreSQL (A–E, 6.1–6.13)»), mergeado el **2026-11-10 02:12:55 UTC**.
- `docs/informe/07-api.md`, sección «Requiere coordinación», documenta lo que
  P4 necesitaba para integrar el front (Dockerfile, compose, CI).
- `docs/informe/continuidad-sesion.md` (§8) registra la coordinación entre
  ambos.

Los informes `07-1-7-2-front-catalogo.md` y `07-3` a `07-7` son de P4 y no se
atribuyen a P3.

## Verificación

```text
$ gh pr view 1 --json reviews
[{"author":{"login":"ivann-02"},"body":"","state":"APPROVED",
  "submittedAt":"2026-11-05T16:19:54Z"}]

$ gh pr view 5 --json reviews   # extracto
[{"author":{"login":"MaJuVer"},"state":"CHANGES_REQUESTED",
  "submittedAt":"2026-11-06T16:08:27Z",
  "body":"## Revisión P2 — Solicito cambios..."}]

$ gh pr view 10 --json reviews
{"reviews":[]}

$ gh pr view 11 --json reviews
{"reviews":[]}

$ gh pr view 23 --json reviews
{"reviews":[]}

$ gh pr view 24 --json reviews
{"reviews":[]}
```

## Estado

**Parcial.** P3 registró reviews en los PR #1, #3 y #7, todos con aprobación y
sin cuerpo. Las tareas 2.3, 2.4, 4.2 y 5.4 no tienen review registrado. La
tarea 0.3 no tiene evidencia. La tarea 2.10 está atribuida a P1 por la
evidencia de Git. El PR #5 no fue revisado por P3, sino por P2.

## Pendientes y observaciones

- **Pendiente:** si las revisiones de 2.3, 2.4, 4.2 y 5.4 se hicieron por otro
  canal, dejarlas asentadas en GitHub o en un documento de revisión. Sin eso,
  el plan las considera no cumplidas.
- **Pendiente:** resolver la atribución de 2.10. La evidencia dice que la
  plantilla la creó P1; el plan dice P3.
- **Observación:** `docs/convenciones.md` no existe. Es un entregable de P1
  para 0.3; conviene que el equipo decida si `docs/contratos.md` lo reemplaza.
- **Observación:** los PR de P3 #13, #15 y #22 se mergearon sin review
  registrado. No es una tarea de revisión de P3, pero afecta la trazabilidad
  de la cadena.
- **No verificable:** no hay evidencia de revisiones orales o fuera de GitHub.
  No se afirman como hechas.
