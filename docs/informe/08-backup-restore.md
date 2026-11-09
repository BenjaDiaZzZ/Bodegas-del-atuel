# Backup y restauración (Tarea 8.8 — P2)

## Backup local (Docker)

### Backup completo con `pg_dump`

```bash
# Desde la raíz del repositorio
source .env
docker compose exec -T db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  --no-owner --no-privileges \
  > backups/bodegas_$(date +%Y%m%d_%H%M%S).sql
```

### Backup solo de datos (para restaurar sobre esquema existente)

```bash
docker compose exec -T db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  --data-only --no-owner --no-privileges \
  > backups/datos_$(date +%Y%m%d_%H%M%S).sql
```

### Backup del volumen Docker (binario)

```bash
docker run --rm -v bodegas_pgdata:/data -v "$(pwd)/backups":/backup \
  alpine tar czf /backup/pgdata_$(date +%Y%m%d_%H%M%S).tar.gz -C /data .
```

## Restauración local

### Restauración completa (reescribe la base)

```bash
# Recrear la base desde cero
./scripts/reset_db.sh

# Restaurar el backup
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  < backups/bodegas_YYYYMMDD_HHMMSS.sql
```

### Restauración solo de datos (mantiene esquema)

```bash
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  < backups/datos_YYYYMMDD_HHMMSS.sql
```

### Restauración del volumen Docker

```bash
docker compose down
docker run --rm -v bodegas_pgdata:/data -v "$(pwd)/backups":/backup \
  alpine tar xzf /backup/pgdata_YYYYMMDD_HHMMSS.tar.gz -C /data
docker compose up -d
```

## Backup en la nube (Aiven)

### Backup automático

Aiven genera backups automáticos del plan Free (1 backup para recuperación).
Se gestionan desde la consola de Aiven: **Servicio → Backups**.

### Backup manual con `pg_dump` contra Aiven

```bash
# La URL de conexión se obtiene de la consola de Aiven (puerto 5432, sslmode=require)
pg_dump "postgresql://USER:PASS@HOST:5432/DB?sslmode=require" \
  --no-owner --no-privileges \
  > backups/aiven_$(date +%Y%m%d_%H%M%S).sql
```

### Restauración en Aiven

```bash
psql "postgresql://USER:PASS@HOST:5432/DB?sslmode=require" \
  < backups/aiven_YYYYMMDD_HHMMSS.sql
```

## Verificación de backup

Después de cada backup, verificar que el archivo contiene datos:

```bash
# El backup debe tener más de 100 líneas y contener los CREATE TABLE
wc -l backups/archivo.sql
grep -c "CREATE TABLE" backups/archivo.sql
```

## Política de backups

| Entorno | Frecuencia | Retención | Método |
|---|---|---|---|
| Local (desarrollo) | Antes de cada `reset_db.sh` | Manual | `pg_dump` + volumen Docker |
| Nube (Aiven) | Automático (diario) | Plan Free (1 backup) | Aiven Backups + `pg_dump` manual |
| Pre-demo | Siempre antes de la demo | Hasta después de la defensa | `pg_dump` completo |
