# Prueba en máquina limpia (Tarea 9.5 — P2)

## Objetivo

Verificar que el proyecto funciona desde cero en una máquina sin dependencias previas, siguiendo solo las instrucciones del repositorio.

## Requisitos de la máquina limpia

- Docker Engine con Docker Compose v2.
- Git.
- Python 3.10+ (opcional, para seed).
- `psql` (opcional, para pruebas manuales).

## Checklist de verificación

### 1. Clonar y configurar

```bash
git clone https://github.com/BenjaDiaZzZ/Bodegas-del-atuel.git
cd Bodegas-del-atuel
cp .env.example .env
# Editar .env si se necesita otro puerto o credenciales
```

- [ ] El clon funciona sin errores.
- [ ] `.env` se crea desde `.env.example`.
- [ ] No hay archivos innecesarios en `.gitignore`.

### 2. Levantar la base

```bash
docker compose up -d
```

- [ ] El contenedor arranca y queda `healthy`.
- [ ] Las migraciones `001`–`008` se aplican automáticamente (docker-entrypoint).
- [ ] Se puede conectar con `psql`:

```bash
docker compose exec db psql -U bodegas -d bodegas_del_atuel -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
# Esperado: 29 tablas
```

### 3. Ejecutar tests

```bash
docker compose exec -T db psql -U bodegas -d bodegas_del_atuel \
  -v ON_ERROR_STOP=1 < db/tests/db_tests.sql
```

- [ ] Todos los tests pasan (`EXIT=0`).
- [ ] No hay errores `FAIL`.

### 4. Cargar seed

```bash
python3 -m venv .venv
.venv/bin/pip install "psycopg[binary]>=3.1" "faker>=20"
.venv/bin/python db/seed/seed.py --scale small --fecha-base 2026-01-01
```

- [ ] El seed ejecuta sin errores (27 pasos).
- [ ] `controles.sql` no reporta errores:

```bash
psql -h localhost -p 5432 -U bodegas -d bodegas_del_atuel \
  -f db/seed/controles.sql
```

### 5. Ejecutar consultas

```bash
psql -h localhost -p 5432 -U bodegas -d bodegas_del_atuel \
  -f consultas/select.sql
```

- [ ] Las 12 consultas (S1–S12) ejecutan sin errores.
- [ ] Los resultados son coherentes (no vacíos donde debería haber datos).

### 6. Concurrencia (opcional)

```bash
PGHOST=localhost PGPORT=5432 PGUSER=bodegas PGDATABASE=bodegas_del_atuel \
  ./db/tests/test_004_concurrency.sh
```

- [ ] El script termina con `OK`.

### 7. Verificaciones de limpieza

- [ ] `git status` muestra solo archivos ignorados o esperados.
- [ ] No quedan archivos temporales en el repositorio.
- [ ] `docker compose down` detiene todo limpiamente.
- [ ] `docker compose down -v` (opcional) elimina el volumen.

## Resultados esperados

| Verificación | Esperado |
|---|---|
| Tablas creadas | 29 |
| Tests `db_tests.sql` | `EXIT=0`, todos OK |
| Seed small | 28 tablas con datos |
| Controles | 0 errores |
| Consultas S1–S12 | 12/12 OK |
| Concurrencia | `OK` |

## Responsable

P2 debe ejecutar esta checklist en un entorno limpio (máquina virtual, contenedor Docker limpio, o cuenta de GitHub Codespaces) y registrar los resultados en este documento.

### Registro de ejecución

| Fecha | Entorno | Resultado | Observaciones |
|---|---|---|---|
| (pendiente) | (a completar) | (a completar) | |
