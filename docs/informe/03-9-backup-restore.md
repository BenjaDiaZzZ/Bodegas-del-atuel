# Backup y restauración locales (Fase 3 · Tarea 3.9)

## Contexto y dependencia con 3.7

La tarea dependía de un `dump_completo.sql.gz` producido por 3.7. El PR #21
cerró 3.7 con `scripts/seed.sh` y los controles de carga, pero **no incluyó un
volcado** en el repositorio. Para no bloquear 3.9, `scripts/backup.sh` genera
ese dump a partir de la base local ya sembrada.

El dataset de prueba se obtuvo con:

```bash
./scripts/reset_db.sh
./scripts/seed.sh --scale small --fecha-base 2026-01-01 \
  --db-url "postgresql://${POSTGRES_USER}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}"
```

La base quedó con las 29 tablas del esquema y los conteos del seed `small`
(26 vinos, 50 comprobantes, 151 renglones, 15 transferencias, etc.).

## `scripts/backup.sh`

```bash
./scripts/backup.sh
./scripts/backup.sh --output /tmp/respaldo.sql.gz
```

Pasos:

1. Lee `.env` y verifica que el servicio `db` esté corriendo.
2. Ejecuta `pg_dump` **dentro del contenedor** (misma versión que el servidor,
   16.15) con `--no-owner`, `--no-privileges`, `--clean`, `--if-exists` y
   `--encoding=UTF8`.
3. Comprime con `gzip -9` a un archivo temporal y lo mueve al destino sólo si
   el pipeline terminó bien.
4. Genera un manifiesto `RUTA.counts` con el conteo exacto de filas por tabla
   base (`pg_class.relkind = 'r'`, esquema `public`), ordenado por nombre.

Salida por defecto:

```text
backups/dump_completo.sql.gz
backups/dump_completo.sql.gz.counts
```

`backups/` y `*.sql.gz` ya están en `.gitignore`; los datos generados no se
versionan.

## `scripts/restore.sh`

```bash
./scripts/restore.sh --db bodegas_del_atuel_restore --recreate
```

Pasos:

1. Valida el nombre de la base destino y **rechaza restaurar sobre
   `POSTGRES_DB`**, para no pisar la base de origen.
2. Si la base destino existe, exige `--recreate`; en ese caso la elimina con
   `dropdb --force` y la vuelve a crear.
3. Restaura con `gunzip -c ... | psql -v ON_ERROR_STOP=1`.
4. Reaplica `db/migrations/007_roles.sql` sobre la base restaurada.
5. Si existe el manifiesto `.counts`, consulta los conteos de la base destino
   y los compara con `diff`. Si no coinciden, muestra la diferencia y sale con
   código 1.

Las opciones `--no-owner` y `--no-privileges` se aplican al generar el dump,
porque el formato es SQL plano; son las que permiten restaurarlo con otro
dueño y volver a conceder privilegios con 007.

## Evidencia de la prueba

Entorno: PostgreSQL 16.15 en Docker (`postgres:16-alpine`), host Fedora 43,
2026-11-09. Dataset `small` con `--fecha-base 2026-01-01`.

### Backup

```text
== Backup de bodegas_del_atuel ==
== Conteos por tabla ==
Dump:    backups/dump_completo.sql.gz (24K)
Conteos: backups/dump_completo.sql.gz.counts (29 tablas)
```

Manifiesto de origen:

```text
analisis_calidad|10
auditoria_precio|0
bodega|5
cepa|12
cliente|15
composicion|67
comprobante|50
distribuidor|4
empleado|10
exportador|4
finca|3
ingreso|20
localidad|18
lote_uva|10
maridaje|8
parcela|7
permiso_exportacion|14
renglon_comprobante|151
renglon_ingreso|53
renglon_transferencia|39
sala|4
socio|7
stock_deposito|26
stock_sala|40
transportista|5
transportista_localidad|15
transferencia|15
vino|26
vino_maridaje|49
```

### Restauración en otra base

```text
== Eliminando base destino existente: bodegas_del_atuel_restore ==
== Creando base destino: bodegas_del_atuel_restore ==
== Restaurando dump_completo.sql.gz en bodegas_del_atuel_restore ==
== Reaplicando privilegios: 007_roles.sql ==
OK: los conteos de bodegas_del_atuel_restore coinciden con el manifiesto (29 tablas).
== Restauración completa: bodegas_del_atuel_restore ==
```

Los `setval` del dump también se restauraron: las secuencias quedaron en los
mismos valores que el origen.

### Privilegios reaplicados

Consultas de comprobación sobre la base restaurada:

```text
app_rw update renglon_comprobante|f
app_rw execute sp_procesar_transferencia|t
reporte_ro select vw_ventas_mensuales_sala|t
app_rw connect|t
```

Es decir, se conserva la regla de 007: `app_rw` no puede actualizar
`renglon_comprobante`, sí ejecuta los procedimientos y `reporte_ro` mantiene
la lectura de las vistas.

### Pruebas negativas

| Caso | Resultado |
|---|---|
| Restaurar sobre la base de origen | `ERROR: la base destino debe ser distinta de la de origen` · exit 1 |
| Restaurar sobre una base existente sin `--recreate` | `ERROR: la base ... ya existe` · exit 1 |
| Manifiesto alterado (`vino|999`) | `FAIL: los conteos ... NO coinciden` + `diff` · exit 1 |

## Decisiones y límites

- Roles y contraseñas son globales del clúster, no de una base. El dump no
  incluye roles: 007 los crea (`NOLOGIN`) y reaplica los `GRANT`. En el mismo
  clúster las contraseñas ya están asignadas; en un clúster nuevo hay que
  ejecutar `scripts/set_role_passwords.sh` (o `ALTER ROLE ... PASSWORD`) para
  que `app_rw` y `reporte_ro` puedan iniciar sesión.
- La verificación compara tablas base, no vistas: el conteo de una vista es
  derivado de sus tablas y no aporta una comprobación independiente.
- El dump usa `--clean --if-exists`, así que también puede aplicarse sobre una
  base que ya tenga el esquema; el script igualmente prefiere una base destino
  limpia.

## Hecho cuando

- El dump se genera y se restaura en una base distinta.
- Los 29 conteos de la base restaurada coinciden con el manifiesto de origen
  (`diff` sin diferencias).
- Los privilegios de 007 quedan reaplicados.
- Una diferencia de conteos hace fallar la restauración con código 1.
