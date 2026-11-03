# Fase 0 · Arranque común

## 0.1 · Repositorio y tablero

Se creó la estructura sugerida en la sección 10.1 del enunciado: carpetas para migraciones, seed, tests, consultas, API, front, scripts y documentación. El repositorio incluye `.gitignore` desde el primer commit para excluir `.env` y archivos generados, y `.env.example` con valores de ejemplo sin secretos.

Se agregó una plantilla de pull request que exige identificar la tarea, describir las pruebas, dejar el párrafo del informe y confirmar que no hay secretos en el diff. La protección de `main`, el tablero de GitHub Projects y la carga de un issue por tarea quedan documentados en `docs/tablero.md`.

**Cómo verificar:** clonar el repositorio, crear una rama, modificar el README y abrir un PR contra `main`.

## 0.2 · Docker Compose inicial

`docker-compose.yml` define un servicio PostgreSQL 16 con un volumen nombrado y un healthcheck. La carpeta `db/migrations/` se monta en `/docker-entrypoint-initdb.d`, de modo que PostgreSQL ejecuta los archivos en orden alfabético cuando se inicializa el volumen por primera vez.

`scripts/reset_db.sh` elimina el volumen, vuelve a levantar la base, espera a que terminen los scripts de inicialización y verifica el estado `healthy` antes de informar la versión del motor. De esta manera, cuando P1 agregue `001_esquema.sql`, la base se puede recrear desde cero con un solo comando.

**Cómo verificar:**

```bash
cp .env.example .env
docker compose up -d
./scripts/reset_db.sh
docker compose ps
```

La base debe quedar sana y sin errores en los logs.

**Verificación realizada el 2/11/2026:** PostgreSQL 16.15 levantó correctamente; se probó el orden con dos migraciones temporales (`001` creó la tabla y `002` insertó sobre ella), la tabla mostró los registros en orden `001` → `002`, y luego se eliminaron esos archivos y se repitió el reset con la carpeta vacía.

## 0.6 · Pre-chequeo de proveedores de nube

La comparación de proveedores, la decisión y los límites del plan quedaron en `docs/informe/08-nube.md`.

## 0.7 · Primer commit de cada integrante

El README contiene la tabla de roles con placeholders y las instrucciones para que cada integrante agregue su nombre en una rama propia y abra un PR. P4 realizó el commit inicial; los otros tres commits deben quedar registrados con los usuarios de Git de cada integrante antes de cerrar la tarea.
