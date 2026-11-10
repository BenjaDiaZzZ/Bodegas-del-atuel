# 8.5 · Despliegue de la API (apoyo de P3)

**Responsable:** P4 (Front e Infraestructura), con apoyo de P3 (API)
**Dependencias:** 8.1–8.4 (proveedor, base y roles en la nube, migraciones y
carga de datos).

## Objetivo

El plan asigna a P4 el despliegue de la API con `sslmode=require`, usando el
rol `app_rw`, y la verificación de `GET /salud` por HTTPS. P3 aporta la
documentación de las variables de entorno que la API necesita. El criterio de
«hecho» es que la API responda por HTTPS.

## Alcance de este informe

Este documento cubre **solo el apoyo de P3**: la tabla de variables de entorno
y la implementación de `POSTGRES_SSLMODE` en la aplicación. El despliegue, la
apertura del puerto, el certificado y la verificación de `/salud` en la nube
son responsabilidad de P4 y se documentan en `docs/informe/08-nube.md`
(L57, L77 y L157).

## Variables de entorno de la API

`api/app/config.py` lee seis variables. La tabla siguiente es la referencia
para el despliegue:

| Variable | Propósito | Default | ¿Obligatoria? | Ejemplo en Aiven |
|---|---|---|---|---|
| `POSTGRES_HOST` | Host de PostgreSQL | `localhost` | No | `pg-bodegas-xxxx.aivencloud.com` |
| `POSTGRES_PORT` | Puerto de PostgreSQL | `5432` | No | `12345` (el que asigne Aiven) |
| `POSTGRES_DB` | Nombre de la base | — | **Sí** | `bodegas_del_atuel` |
| `DB_USER` | Rol de la API | `app_rw` | No | `app_rw` |
| `DB_PASSWORD` | Contraseña de `app_rw` | — | **Sí** | valor del gestor de secretos |
| `POSTGRES_SSLMODE` | Modo SSL de libpq | `prefer` | No | `require` |

Notas:

- `POSTGRES_DB` y `DB_PASSWORD` son obligatorias: `config.py` falla rápido si
  faltan (`_required`, L59-63).
- `DB_USER` debe ser `app_rw`, nunca el propietario `bda_owner` ni un
  superusuario. La API no necesita DDL.
- En producción se usa `POSTGRES_SSLMODE=require`. El default `prefer` existe
  para no romper PostgreSQL local sin SSL.
- Las variables `CLOUD_DB_*`, `CLOUD_ADMIN_*` y `BDA_OWNER_PASSWORD` de
  `.env.example` (L18-26) son para los scripts de migración y administración,
  no para la API. No deben cargarse en el contenedor de la API.

## Implementación en `config.py`

`api/app/config.py` define los valores por defecto (L6-9) y la lista de modos
SSL aceptados (L10-12):

```python
DEFAULT_SSLMODE = "prefer"
VALID_SSLMODES = frozenset(
    {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
)
```

`Settings.from_env()` lee las seis variables (L26-33). `_sslmode_from_env()`
(L48-56) valida el valor y lanza `RuntimeError` si no está en la lista; no cae
silenciosamente en un modo inseguro. `build_conninfo()` en `api/app/db.py`
incluye el `sslmode` en la cadena de conexión.

## PR #40 — SSL para Aiven

El **PR #40** («fix(api): configure SSL for Aiven connections»), del autor
ivann-02, fue mergeado el **2026-11-10 05:36:57 UTC** por BenjaDiaZzZ. El commit
de la rama es `fbb4cc6` y el commit de merge es `70c714b2`.

Archivos modificados:

| Archivo | Cambio |
|---|---|
| `api/app/config.py` | +17 líneas: `POSTGRES_SSLMODE`, validación y default. |
| `api/app/db.py` | +1 línea: `sslmode` en `build_conninfo()`. |
| `.env.example` | +5 líneas: plantilla de `POSTGRES_SSLMODE` y notas de Aiven. |
| `api/Dockerfile` | +3/−2 líneas para el entorno de despliegue. |
| `api/tests/test_db.py` | +76 líneas: 6 pruebas de SSL y no fuga de contraseña. |
| `docs/informe/07-api.md` | +15 líneas: tabla y ejemplo de variables. |

La tabla de variables de `docs/informe/07-api.md` (L100-109) y el bloque de
ejemplo (L120-129) son la fuente original del apoyo de P3. Este informe los
ordena para el despliegue y agrega la columna de ejemplo de producción.

## Ejemplo de configuración de producción

Sin secretos reales en el repositorio. El archivo `.env` se crea en el
servidor de P4 y no se commitea:

```dotenv
POSTGRES_HOST=pg-bodegas-xxxx.aivencloud.com
POSTGRES_PORT=12345
POSTGRES_DB=bodegas_del_atuel
DB_USER=app_rw
DB_PASSWORD=<contraseña de app_rw, desde el gestor de secretos>
POSTGRES_SSLMODE=require
```

El `Dockerfile` de la API no incluye credenciales: las variables se pasan con
`--env-file` o con el entorno del servicio. La aplicación falla al arrancar si
falta `POSTGRES_DB` o `DB_PASSWORD`, lo que evita un arranque a medias.

## Verificación

```text
$ sed -n '6,12p' api/app/config.py
DEFAULT_HOST = "localhost"
DEFAULT_PORT = 5432
DEFAULT_USER = "app_rw"
DEFAULT_SSLMODE = "prefer"
VALID_SSLMODES = frozenset(
    {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
)

$ gh pr view 40 --json number,title,mergedAt   # extracto
{"mergedAt":"2026-11-10T05:36:57Z","number":40,
 "title":"fix(api): configure SSL for Aiven connections"}

$ git log --oneline --all | grep -i ssl
fbb4cc6 fix(api): configure SSL for Aiven connections
```

## Estado

**Hecho (apoyo de P3).** Las variables de entorno están documentadas, la API
valida `POSTGRES_SSLMODE` y el PR #40 dejó la configuración de SSL lista para
Aiven. El despliegue efectivo y la verificación de HTTPS/`salud` son de P4.

## Pendientes y observaciones

- **Pendiente de P4:** verificar `GET /salud` por HTTPS contra la instancia de
  Aiven y dejar la evidencia. Este informe no la cubre.
- **Discrepancia:** `docs/informe/08-nube.md` L157 dice que la base queda
  «lista para que P3 despliegue la API», pero el plan asigna el despliegue a
  P4 con apoyo de P3. Conviene corregir la atribución en ese informe o aclarar
  que P3 solo documenta variables.
- **Discrepancia de rama local:** `origin/main` local está en `a43e63b` y no
  contiene el commit de merge del PR #40 (`70c714b2`). El PR figura mergeado en
  GitHub; la referencia local está desactualizada. No se hizo `fetch` ni
  `pull` porque el alcance de este informe es de solo lectura.
- **No verificable:** no se probó la conexión real a Aiven desde este entorno;
  no hay credenciales ni acceso a la instancia.
