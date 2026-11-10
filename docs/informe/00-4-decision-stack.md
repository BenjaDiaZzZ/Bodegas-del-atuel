# 0.4 · Decidir el stack

**Responsable:** P3 (API)
**Revisa:** todos los integrantes
**Dependencias:** 0.1 (repositorio) y 0.2 (tablero).

## Objetivo y criterio de aceptación

El plan pide abrir un issue de decisión con la propuesta de stack, esperar votos
durante 24 horas y cerrar el issue con la decisión y su justificación. La
recomendación del enunciado es FastAPI + psycopg 3 con pool para la API y
React + Vite para el front, con prohibición expresa de ORM o query builder. El
criterio de «hecho» es que haya un stack elegido y anotado en el `README`.

## Evidencia disponible

### Issue de decisión

`gh issue list --state all` devuelve un único issue, el **#6**
(`[P1][2.1] Completar cambios de esquema pendientes del review de 002`), que no
es un issue de decisión de stack. No hay evidencia de una propuesta publicada,
de votos durante 24 horas ni de un cierre con justificación.

### README

La sección `## Stack` del `README.md` (líneas 16-21) declara:

- PostgreSQL 16 (compatible con 14 o superior).
- Docker y Docker Compose.
- API REST con driver nativo y SQL directo (sin ORM).
- Front libre que consume únicamente la API.

El README fija la restricción técnica principal (sin ORM, driver nativo) pero no
nombra el framework de la API ni el del front.

### Stack real de la API

`api/requirements.txt` fija las versiones efectivamente usadas:

```text
fastapi==0.162.2
uvicorn==0.54.0
psycopg[binary]==3.3.8
psycopg-pool==3.3.3
pytest==9.2.0
httpx==0.28.1
```

`api/openapi.yaml` línea 10 refuerza la decisión: «La API usa SQL puro
parametrizado y un driver nativo (psycopg 3). No hay ORM.»

### Stack real del front

`front/package.json` solo declara `vite` (`^8.3.6`) como dependencia de
desarrollo. `front/src/main.js` importa módulos propios (`router.js`,
`pages/*.js`) y no hay ninguna referencia a React en `front/` ni en
`front/package-lock.json` (`grep -c '"react"' front/package-lock.json` devuelve
`0`). El front es JavaScript modular con Vite, no React.

Esto es una **discrepancia con la recomendación del plan**: la API sí sigue la
recomendación (FastAPI + psycopg 3), pero el front no usa React. La evidencia
disponible no permite saber si la diferencia fue una decisión del equipo o un
cambio posterior de P4; no hay issue ni acta que lo registre.

## Stack efectivamente usado

| Capa | Tecnología | Evidencia |
|---|---|---|
| Base de datos | PostgreSQL 16 (compatible con 14+) | `README.md` L18; migraciones `db/migrations/001`–`008` |
| Contenedores | Docker y Docker Compose | `README.md` L19; `docker-compose.yml` |
| Framework de la API | FastAPI 0.162.2 | `api/requirements.txt` |
| Servidor ASGI | Uvicorn 0.54.0 | `api/requirements.txt` |
| Driver de base | psycopg 3.3.8 (binario) | `api/requirements.txt`; `api/openapi.yaml` L10 |
| Pool de conexiones | psycopg-pool 3.3.3 | `api/requirements.txt` |
| Pruebas de API | pytest 9.2.0 + httpx 0.28.1 | `api/requirements.txt`; `api/tests/` |
| Bundler del front | Vite 8.3.6 | `front/package.json` |
| Framework del front | JavaScript modular, sin framework | `front/src/main.js`; ausencia de React en `package-lock.json` |

## Justificación

- **FastAPI + psycopg 3:** permite SQL parametrizado directo, sin ORM ni query
  builder, y expone el contrato OpenAPI con validación de request. Es la
  combinación recomendada por el enunciado.
- **psycopg-pool:** la API abre conexiones por operación; el pool evita el costo
  de reconectar y encaja con el límite de conexiones de Aiven documentado en
  `docs/informe/08-nube.md`.
- **PostgreSQL 16:** es la versión usada en desarrollo y en CI
  (`docker-compose.yml` usa `postgres:16-alpine`); las migraciones se probaron
  también sobre PostgreSQL 14.24 y 18.6 según el body del PR #2 y
  `docs/informe/08-nube.md`.
- **Vite:** el front se sirve como aplicación estática que consume la API; Vite
  cubre el build y el proxy de desarrollo sin agregar un framework.

## Verificación

```text
$ cat api/requirements.txt
fastapi==0.162.2
uvicorn==0.54.0
psycopg[binary]==3.3.8
psycopg-pool==3.3.3
pytest==9.2.0
httpx==0.28.1

$ cat front/package.json
"devDependencies": { "vite": "^8.3.6" }

$ grep -c '"react"' front/package-lock.json
0

$ gh issue list --state all
6  CLOSED  [P1][2.1] Completar cambios de esquema pendientes del review de 002
```

## Estado

**Parcial.** La decisión existe de hecho y está implementada, y la restricción
«driver nativo / sin ORM» quedó anotada en el README. Faltan dos piezas del
entregable formal:

1. El issue de decisión con la propuesta, los votos de 24 horas y el cierre
   justificado.
2. Completar el README con el stack concreto: FastAPI, psycopg 3 con pool y
   Vite. La mención a React debe resolverse como decisión del equipo, porque el
   front actual no la usa.

## Pendientes y observaciones

- **Pendiente:** abrir o documentar el issue de decisión y dejar registro de la
  votación. Es una decisión de equipo; no se creó desde este informe.
- **Pendiente:** actualizar la sección `## Stack` del README con los nombres y
  versiones concretas. También conviene aclarar que el front es JavaScript
  modular con Vite, para que el README no contradiga al código.
- **Discrepancia:** el plan recomienda React + Vite; el front real es Vite sin
  React. No hay evidencia registrada de la decisión que produjo la diferencia.
- **No verificable:** no hay acta, issue ni comentario que documente la
  aprobación unánime del stack.
