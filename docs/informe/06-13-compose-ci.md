# API Fase 6: revisión 6.11/6.13 y cierre de compose + CI (P4)

Este informe cubre la revisión de P4 sobre el PR #30 de P3 (`feature/p3-api-fase6`)
y el trabajo de cierre que quedó del lado de P4: servicio `api` en
`docker-compose.yml`, inicialización de contraseñas de roles y ejecución de la
suite de API en CI.

## Revisión de 6.11 · pruebas automáticas

- **Suite**: `api/tests` tiene **176 tests** (el mínimo pedido era 8) y CI los
  corre desde el job nuevo `api`.
- **Violaciones de reglas cubiertas** (verificadas en vivo además de por tests):
  - venta sin stock → `409` `P0001` `regla: RN-09`
  - transición inválida (procesar antes de terminar) → `409` `P0001` `regla: RN-11`
  - composición que no suma 100 → `409` `regla: RN-05` (trigger diferido, falla en COMMIT)
  - **precio negativo → `422` `23514`** (`ck_vino_precio_venta`)
  - duplicado `23505` → `409`; FK `23503` → `409/422`; validación de request → `400`
- **Hallazgos de la revisión** (publicados como `CHANGES_REQUESTED` en el PR #30):
  1. Tests dependientes de zona horaria: 7 tests comparan `date.today()` del host
     con `CURRENT_DATE` de la base (UTC). Entre las 21:00 y las 00:00 ART fallan.
  2. Falta el test puntual de precio negativo → 422 (el mecanismo funciona; solo
     estaba cubierto el 422 por `graduacion`).
- Se pidió además, como seguimiento no bloqueante para el front, `GET /cepas`
  (y opcionalmente `GET /maridajes`) para poblar el formulario de 7.3.

## Revisión de 6.13 · Dockerfile y coherencia

- `docker build -f api/Dockerfile .` construye sin errores; el contenedor queda
  `healthy` y `GET /salud` responde 200 contra PostgreSQL real.
- Comparación `GET /openapi.json` vs `api/openapi.yaml`: **26/26 operaciones**
  con ruta real, sin faltantes ni sobrantes.
- Observación no bloqueante: el OpenAPI autogenerado no declara los códigos
  400/404/409/503 del contrato (solo el 422 genérico) y el `operationId` de
  `/salud` difiere. Las rutas coinciden; es documentación.

## Cierre de compose (P4)

`docker-compose.yml` ahora define:

- **`api`**: build desde `api/Dockerfile` (contexto raíz), `env_file: .env`,
  `POSTGRES_HOST=db`, puerto `${API_PORT:-8000}:8000`, y `depends_on` de `db`
  healthy y `db-init` completado. El healthcheck viene del Dockerfile.
- **`db-init`**: servicio one-shot que fija las contraseñas de `app_rw` y
  `reporte_ro` desde `.env`. Es necesario porque 007 crea los roles `NOLOGIN` y
  `docker compose up` no ejecuta `scripts/set_role_passwords.sh`. Usa `\getenv`
  de `psql` para no exponer las contraseñas en la línea de comandos y reintenta
  hasta 30 veces: en el primer arranque, PostgreSQL pasa por un servidor
  temporal y un reinicio, y el healthcheck puede dar `healthy` justo en esa
  ventana.

También se agregó `API_PORT=8000` a `.env.example`.

## Cierre de CI (P4)

Nuevo job **`API (pytest y compose)`** en `.github/workflows/ci.yml`:

1. Crea el `.env` de CI y recrea la base con `./scripts/reset_db.sh`.
2. Instala `api/requirements.txt` con Python 3.11.
3. Corre `python -m pytest api/tests -q` con las credenciales de CI
   (`app_rw` + superusuario de fixtures).
4. Levanta `docker compose up -d --build` y espera `GET /salud`; si no responde
   muestra los logs y falla. El `trap` baja el stack al terminar.

Además, el trigger `pull_request` dejó de filtrar por `main`: así el CI corre
también en PRs apilados como este, que tienen base `feature/p3-api-fase6`.

## Verificación local

```text
docker compose up -d --build
db        healthy
db-init   Exited (0)  ALTER ROLE x2
api       healthy
GET /salud  200  {"status":"ok","db":true,"version":"PostgreSQL 16.15",...}
GET /vinos  200  {"data":[],"meta":{"page":1,"per_page":5,"total":0,"total_pages":0}}
pytest api/tests  176 passed
```

La suite se corrió con `TZ=UTC` porque los 7 tests de fecha siguen pendientes
del fix pedido en el PR #30; en los runners de GitHub (UTC) el job pasa igual.

## Rama y merge

Esta rama (`feat/p4-compose-ci-api`) está **apilada sobre `feature/p3-api-fase6`**
porque referencia `api/Dockerfile`. Cuando se mergee #30, se retargetea a `main`
y se puede mergear este PR.
