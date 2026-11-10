# 7.7 Errores y Compose

## Objetivo

Mostrar mensajes de error tal como los devuelve la API, sin reemplazarlos por uno genérico. Agregar el front al docker-compose.yml. Hecho cuando: docker compose up levanta base, API y front, y no hay lógica de importes ni de stock en el cliente.

## Cambios realizados

* `front/Dockerfile`: build multi-stage con Node 24 y Nginx 1.27. `ARG VITE_API_URL` con valor default `/api`. Build estático a `/usr/share/nginx/html`.
* `front/nginx.conf`: proxy `/api/` → `http://api:8000/`. SPA fallback `try_files`.
* `front/.dockerignore`: excluye `node_modules`, `dist`, `.e2e*`.
* `docker-compose.yml`: servicio `front` con build `./front`, puerto `${FRONT_PORT:-8080}:80`, depends_on `api` saludable, arg `VITE_API_URL=/api`.
* `.env.example`: variable `FRONT_PORT=8080`.
* `.github/workflows/ci.yml`:
  * Job `front` que corre `npm ci` y `npm run build`.
  * Job `api` verificación compose ahora comprueba API `/salud`, front `/` y proxy `/api/salud`.

## Verificación local

```
docker compose up -d --build
```

Contenedores:
* bodegas_del_atuel_db healthy
* bodegas_del_atuel_db_init completed
* bodegas_del_atuel_api healthy
* bodegas_del_atuel_front healthy

Pruebas de servicio:
* `curl http://127.0.0.1:8000/salud`
```json
{"status":"ok","db":true,"version":"PostgreSQL 16.15","timestamp":"..."}
```
* `curl http://127.0.0.1:8080/` → HTTP 200, contiene `<main id="app">` y assets.
* `curl http://127.0.0.1:8080/api/salud` → HTTP 200, mismo JSON que API.
* `curl http://127.0.0.1:8080/api/reportes/top-vinos?limite=3` → HTTP 200.

No hay cálculo de importes ni stock en el cliente. Los pages usan `htmlError` con `e.message` verbatim de la API.

## Notas

* El front se compila con `VITE_API_URL=/api`, por lo que las peticiones al API se realizan vía nginx proxy dentro de la red compose, evitando CORS.
* La base y API se inicializan con el flujo existente `scripts/reset_db.sh` y `db-init`.
* El CI ahora valida que `docker compose up` levante base, API y front de forma conjunta.
