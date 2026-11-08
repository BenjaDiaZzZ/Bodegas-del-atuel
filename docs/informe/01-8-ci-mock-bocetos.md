# 1.8 · CI, mock de la API y bocetos

**Responsable:** P4 (Front e Infraestructura)
**Dependencias:** 1.3 (`db/migrations/001_esquema.sql`) y 1.7 (`api/openapi.yaml`), ambas mergeadas en `main`.

## Objetivo

Dejar preparada la base de infraestructura de la Fase 1:

- Un workflow de integración continua que aplique las migraciones sobre PostgreSQL 16.
- Un mock de la API generado desde `api/openapi.yaml`, para que P3 pueda trabajar contra el contrato antes de implementar los endpoints.
- Cinco bocetos de las pantallas principales del frontend.

Esta tarea no implementa todavía la API ni el frontend: solamente prepara el CI, el contrato ejecutable y los bocetos.

## Entregables

### 1. Workflow de CI

Archivo: `.github/workflows/ci.yml`.

Se ejecuta en cada `push` y `pull_request` contra `main` y tiene dos jobs:

- **`db`**: genera un `.env` efímero con credenciales exclusivas del runner y ejecuta `./scripts/reset_db.sh`, el mismo camino que usa un desarrollador (Docker Compose, entrypoint, healthcheck y contraseñas de roles). Al finalizar, un bloque `DO` verifica que existan al menos 29 tablas, 4 vistas y los roles `bda_owner`, `app_rw` y `reporte_ro`; si falta algo, el job falla.
- **`contrato`**: valida `api/openapi.yaml` con Redocly, levanta el mock de Prism en el puerto `4010` y comprueba que `GET /salud` responda con HTTP 200.

El `.env` generado en CI no se commitea. La aplicación de migraciones queda centralizada en `scripts/reset_db.sh` y el entrypoint de PostgreSQL, sin un bucle duplicado en el workflow.

### 2. Mock de la API

Archivo: `scripts/mock_api.sh`.

El script verifica que exista `api/openapi.yaml` y que `npx` esté disponible, y luego ejecuta Prism:

```bash
npx --yes @stoplight/prism-cli@5 mock api/openapi.yaml --port "${PRISM_PORT:-4010}"
```

Uso:

```bash
./scripts/mock_api.sh
curl http://127.0.0.1:4010/salud
```

Se puede cambiar el puerto con la variable `PRISM_PORT`.

### 3. Bocetos

Archivos en `docs/bocetos/`:

- `01-catalogo-vinos.svg`: filtros, listado de vinos y paginación.
- `02-alta-edicion-vino.svg`: formulario de alta/edición, cepas, presentaciones y vista previa.
- `03-nueva-venta.svg`: selección de cliente, renglones, descuento y total.
- `04-transferencias.svg`: listado, detalle, estados y acciones de una transferencia.
- `05-tablero-reportes.svg`: indicadores, ventas por sala, top de vinos y accesos a reportes.

Los bocetos son de baja fidelidad y sirven para acordar estructura y flujo, no para definir estilos finales.

## Verificación local

### Migraciones

Se recreó la base con `./scripts/reset_db.sh` y se aplicaron las migraciones disponibles:

```text
001_esquema.sql
002_constraints.sql
006_vistas.sql
007_roles.sql
PostgreSQL 16.15
```

Después se ejecutó el bloque de verificación del job `db` contra la base recreada:

```text
NOTICE:  Verificación OK: tablas=29, vistas=4, roles=3
```

Para comprobar que la verificación realmente falla, se ejecutó el mismo bloque contra una base vacía:

```text
exit=3
ERROR:  Verificación falló: tablas=0, vistas=0, roles=3
```

Los roles `bda_owner`, `app_rw` y `reporte_ro` quedaron creados.

### Contrato

```text
api/openapi.yaml: validated in 184ms
Woohoo! Your API description is valid.
You have 2 warnings.
```

Los avisos son de estilo (URL de `localhost` y ausencia de respuesta `4XX` en `/salud`); no invalidan el contrato.

### Mock

```text
Mock disponible en http://127.0.0.1:4011
$ curl http://127.0.0.1:4011/salud
{"status":"ok","db":true,"version":"PostgreSQL 16.15","timestamp":"2026-11-05T13:30:00Z"}
```

Prism respondió HTTP 200 usando el ejemplo declarado en el contrato.

## Alcance y siguientes pasos

- El workflow todavía no ejecuta `db/tests/db_tests.sql`; esa integración corresponde a la tarea 2.8, cuando estén mergeadas las funciones y los triggers.
- El mock es una herramienta de desarrollo: no reemplaza la implementación real de la API (tarea 6.1).
- Los bocetos se usarán como referencia para las pantallas de P4 en las fases siguientes.
