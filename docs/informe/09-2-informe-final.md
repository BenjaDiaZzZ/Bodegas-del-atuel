# 9.2 · Informe final (estado y trazabilidad)

**Responsable:** P3 (API)
**Dependencias:** todas las fases anteriores; en particular los informes de
P1, P2 y P4 en `docs/informe/`.

## Objetivo

Unir los documentos `docs/informe/NN-*.md` en un informe final que siga la
estructura de la sección 10.2 del enunciado: introducción, modelo, integridad,
carga, índices, consultas, API y front, nube y conclusiones. El criterio de
«hecho» es que estén los nueve capítulos.

## Estado

**Hecho.** El consolidado está en `docs/informe/informe-final.md`: 894 líneas,
título y nueve capítulos en el orden de la sección 10.2, con tabla de estado por
capítulo y referencias a los informes parciales.

`docs/informe/07-api.md` (L370) mencionaba la consolidación como pendiente de P3
y `docs/informe/continuidad-sesion.md` (L82) registraba 9.2 como «parcial»; ambos
son estados previos al cierre de la Fase 6 y quedaron superados por este
documento.

## Anexo · Mapeo capítulo → fuentes

La tabla conserva el mapeo usado para redactar el consolidado; la columna
«Estado» describe el estado de cada fuente al momento de la auditoría, no el del
capítulo ya redactado.

| # | Capítulo (10.2) | Fuentes disponibles | Estado |
|---|---|---|---|
| 1 | Introducción | `00-arranque.md`, `README.md` | Parcial: hay material, falta redacción integrada. |
| 2 | Modelo | `01-modelado.md`, `docs/justificaciones.md`, `docs/normalizacion.md`, `docs/diccionario.md` | Parcial: `01-modelado.md` solo contiene las secciones de P2 (1.4–1.6); faltan DER, esquema relacional y `001_esquema.sql` de P1. |
| 3 | Integridad | `02-constraints.md`, `02-tests-constraints.md`, `03-concurrencia.md`, `docs/trazabilidad.md` | Completo: constraints, pruebas, concurrencia y trazabilidad RN-01..RN-15. |
| 4 | Carga | `04-carga.md` | Completo: tareas 3.1–3.7, con orden de carga y controles. |
| 5 | Índices | `05-indices.md` | Completo: tareas 4.1–4.7, con mediciones y `EXPLAIN`. |
| 6 | Consultas | `consultas/select.sql`, `consultas/insert.sql`, `consultas/update.sql`, `consultas/delete.sql`; PRs #24 y #27 | Parcial: el SQL existe, pero no hay un informe dedicado que explique S1–S12, U1–U6 e I1–I6. |
| 7 | API y front | `07-api.md`, `06-13-compose-ci.md`, `07-1-7-2-front-catalogo.md`, `07-3` a `07-7` | Completo en piezas: API y front documentados por separado; falta el capítulo unificado. |
| 8 | Nube | `08-nube.md`, `08-backup-restore.md`, `03-9-backup-restore.md` | Parcial: 8.1–8.4 documentadas; 8.5 (despliegue de la API) sigue abierto. |
| 9 | Conclusiones | — | Pendiente: no hay borrador. |

## Historia · Qué faltaba antes de la consolidación

Los seis puntos describen el estado previo. El consolidado resolvió la
redacción, pero no las dependencias de contenido: el DER escrito y el cierre de
8.5 siguen abiertos y así se declaran en `informe-final.md`.

1. **Introducción:** redactar un texto de apertura que presente el sistema,
   el alcance y la organización del equipo. Las fuentes existen, pero no están
   integradas.
2. **Modelo:** completar `01-modelado.md` con las secciones de P1 (DER, esquema
   relacional y explicación de `001_esquema.sql`). Hoy el archivo solo tiene
   las secciones de P2.
3. **Consultas:** crear un capítulo que explique las consultas S1–S12, U1–U6,
   I1–I6 y D1–D6, con su propósito y su relación con los reportes de la API.
   El SQL está en `consultas/` y los PRs #24/#27, pero no hay informe.
4. **Nube:** cerrar 8.5 (despliegue de la API por HTTPS y verificación de
   `/salud`) y luego resumir 8.1–8.5 en el capítulo.
5. **Conclusiones:** redactar el cierre con resultados, limitaciones y
   aprendizajes. No hay borrador.
6. **Consolidación:** unificar los ocho capítulos en un solo documento, con
   numeración y referencias cruzadas, sin duplicar el detalle de los informes
   parciales.

## Criterios aplicados en la consolidación

1. Congelar las fuentes: no seguir editando los informes parciales mientras se
   arma el consolidado.
2. Crear `docs/informe/informe-final.md` con el orden de la sección 10.2.
3. Por cada capítulo, escribir una introducción breve y remitir al informe
   parcial para el detalle, en lugar de copiar tablas y salidas completas.
4. Verificar que las cifras citadas coincidan con la fuente: el número de
   pruebas de la API tiene varias cifras (174/176/178/184) y el consolidado deja
   constancia de la discrepancia sin inventar una cifra única.
5. Revisar que las tareas de P3, P2 y P4 estén atribuidas correctamente; en
   particular, no atribuir a P3 los informes de front 7.1–7.7 ni el despliegue
   de 8.5.
6. Cerrar con una lista de verificación de los nueve capítulos y una tabla de
   trazabilidad tarea → sección → evidencia.

## Verificación

Estado previo a la consolidación (auditoría):

```text
$ git ls-tree --name-only HEAD docs/informe/
docs/informe/00-arranque.md
docs/informe/01-8-ci-mock-bocetos.md
docs/informe/01-modelado.md
docs/informe/02-8-runner-tests.md
docs/informe/02-constraints.md
docs/informe/02-tests-constraints.md
docs/informe/03-9-backup-restore.md
docs/informe/03-concurrencia.md
docs/informe/04-carga.md
docs/informe/05-indices.md
docs/informe/06-13-compose-ci.md
docs/informe/07-1-7-2-front-catalogo.md
docs/informe/07-3-alta-edicion-vino.md
docs/informe/07-4-nueva-venta.md
docs/informe/07-5-transferencias.md
docs/informe/07-6-tablero.md
docs/informe/07-7-errores-compose.md
docs/informe/07-api.md
docs/informe/08-backup-restore.md
docs/informe/08-nube.md
docs/informe/09-maquina-limpia.md
docs/informe/continuidad-sesion.md

$ grep -n "9.2" docs/informe/07-api.md
370:  coherencia final OpenAPI/rutas, 9.2 consolidación del informe final.

$ grep -n "^## " docs/informe/01-modelado.md
7:## 1.4 · Catálogos en CSV (P2)
56:## 1.5 · Normalización a 3FN (P2)
87:## 1.6 · Diccionario de datos (P2)
```

Verificación del consolidado:

```text
$ grep -c "" docs/informe/informe-final.md
894

$ grep "^## " docs/informe/informe-final.md
## 1. Introducción
## 2. Modelo
## 3. Integridad
## 4. Carga
## 5. Índices
## 6. Consultas
## 7. API y front
## 8. Nube
## 9. Conclusiones

$ git status --short docs/informe/
?? docs/informe/09-2-informe-final.md
?? docs/informe/informe-final.md
?? docs/informe/revisiones-p3.md
```

La salida completa incluye además los informes agregados en esta sesión
(`00-4`, `00-5`, `01-7`, `02-5`, `06-11`, `08-5`), todos sin seguimiento; aquí se
muestran solo los dos archivos de 9.2. El consolidado se llama
`docs/informe/informe-final.md`; no se creó `docs/informe/09-informe-final.md` y
no se hicieron commits.

## Estado por capítulo

| Estado | Capítulos |
|---|---|
| Redactado en `informe-final.md` | los nueve |

El criterio de «hecho» (nueve capítulos) se cumple. El contenido de cada capítulo
mantiene el estado honesto de su fuente: hay tareas **Hecho**, otras **Parcial**,
**Pendiente** y **No verificable** (por ejemplo, el DER escrito y la restauración
en la nube), y esas distinciones se conservan en las tablas del consolidado.

## Pendientes y observaciones

- **Hecho:** el documento consolidado existe y cubre los nueve capítulos.
- **Deuda de P1:** el DER y el esquema relacional escritos no existen como
  archivos, y el consolidado lo declara **No verificable** en vez de inventarlo.
- **Deuda de P4:** 8.5 (despliegue de la API por HTTPS y verificación de
  `/salud`) sigue abierto; el capítulo 8 lo registra como **Parcial**.
- **Pendiente de verificación:** las cifras de pruebas de la API
  (174/176/178/184) no se reconciliaron porque el entorno no tiene `psycopg` y no
  se pudo correr `pytest --collect-only`; el capítulo 7 deja constancia.
- **Observación:** `continuidad-sesion.md` dice que `07-api.md` está completo
  hasta 6.6, pero la Fase 6 se cerró después. Ese estado quedó desactualizado y
  no se usó como fuente del consolidado.
