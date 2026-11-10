# Despliegue en la nube · Pre-chequeo de proveedores

Consulta realizada el **2 de noviembre de 2026** sobre la documentación oficial de cada proveedor. Los planes gratuitos cambian con frecuencia, así que esta tabla debe revisarse antes de ejecutar la tarea 8.1.

## Criterios

El enunciado exige que el puerto de PostgreSQL **no quede abierto a todo internet**. Por eso no alcanza con que el proveedor ofrezca SSL: también tiene que permitir restringir el acceso por IP, ofrecer una red privada o permitir deshabilitar el acceso público.

## Tabla comparativa

| Criterio | Aiven for PostgreSQL Free | Render Postgres Free | Supabase Free | Neon Free |
|---|---|---|---|---|
| ¿Pide tarjeta? | No | No para el plan Free | No para el plan Free | No |
| Restricción por IP | Sí, `ip_filter` con rangos CIDR | Sí, IP allow list para la base (también en Free) | Sí, Network Restrictions | Solo en el plan Scale (pago); en Free no hay IP Allow |
| Red privada | No en Free (no permite VPC) | Sí, URL interna entre servicios de la misma región | No aplica al plan Free | Private Networking solo en Scale |
| Almacenamiento | 1 GB | 1 GB | 500 MB de base | 1 GB por proyecto |
| Inactividad | Se apaga tras inactividad prolongada, con aviso; se puede encender | La base Free expira a los **30 días**; el servicio web Free se duerme a los 15 min | El proyecto se pausa tras **7 días** sin actividad | Compute se suspende a los 5 min (scale to zero) |
| Límite de conexiones | `max_connections = 20`, sin pooling | 100 conexiones; sin pooling en Free | 60 directas y 200 clientes del pooler (pool por defecto 15) | ~97 directas en compute mínimo; pooler hasta 10.000 clientes |
| SSL | Sí, datos cifrados en tránsito y en disco | Sí, TLS obligatorio en conexiones externas | Sí, SSL enforcement disponible | Sí, SSL/TLS obligatorio |
| Backups | Sí, un backup para recuperación ante desastres | No en Free | No descargables en Free | Restauración instantánea de 6 h, 1 snapshot manual |
| Duración del plan | Sin límite de tiempo | Base Free expira a los 30 días | Sin límite, pero con pausas por inactividad | Sin límite |
| Observaciones | 1 CPU, 1 GB RAM, un servicio por tipo, sin SLA | Sin pooling ni backups en Free; se puede pasar a pago desde USD 6/mes | 2 proyectos activos; conexión directa IPv6 y pooler IPv4 | La restricción por IP queda fuera del plan gratuito |

Fuentes oficiales:

- Aiven: <https://aiven.io/docs/products/postgresql/concepts/pg-free-tier>, <https://aiven.io/docs/platform/howto/restrict-access>, <https://aiven.io/pricing/postgresql>
- Render: <https://render.com/docs/free>, <https://render.com/docs/postgresql-creating-connecting>, <https://render.com/pricing>
- Supabase: <https://supabase.com/pricing>, <https://supabase.com/docs/guides/platform/network-restrictions>, <https://supabase.com/docs/guides/platform/compute-and-disk>
- Neon: <https://neon.com/docs/introduction/plans>, <https://neon.com/docs/introduction/ip-allow>, <https://neon.com/faqs/managed-postgres-databases-free-tier>

## Decisión

**Proveedor principal: Aiven for PostgreSQL Free**, con la API desplegada en un servidor virtual con IP pública estática y firewall.

- La base queda en Aiven con `ip_filter` limitado a la IP del servidor de la API.
- La API se conecta con `sslmode=require` usando el rol `app_rw`.
- El servidor virtual puede ser una instancia gratuita (por ejemplo, Oracle Cloud Always Free u otra equivalente) con Docker y firewall; solo se exponen los puertos 80/443 de la API y del front.
- Ventajas: no pide tarjeta, no expira, incluye backups y permite restringir por IP.
- Límites a tener en cuenta: 1 GB de disco y solo 20 conexiones directas. La API debe usar un pool pequeño (por ejemplo, máximo 5 conexiones) y evitar conexiones ociosas.
- Si el servicio se apaga por inactividad, se enciende desde la consola antes de la demo.

**Proveedor de respaldo: Render Free**, con base y API en la misma región y workspace.

- La API usa la URL interna de Render y se desactiva el acceso externo a la base (o se limita por IP), por lo que el puerto no queda abierto a internet.
- Ventajas: IP allow list disponible en Free, 1 GB, 100 conexiones y TLS en conexiones externas.
- Riesgo: la base Free expira a los 30 días. Para la defensa hay que crearla de nuevo y restaurar el backup, o pasar la base a un plan pago de USD 6/mes. Por eso queda como respaldo y no como principal.

**Descartados para el plan gratuito:**

- **Neon:** cumple SSL, almacenamiento y conexiones, pero IP Allow solo está disponible en el plan Scale. Sin una IP fija o un firewall propio no cumple el requisito de restringir el acceso.
- **Railway:** no ofrece control de acceso por IP para el proxy TCP de PostgreSQL. Se puede dejar la base solo en la red privada, pero entonces no es accesible desde fuera del proyecto sin un workaround.

## Consecuencias para las tareas siguientes

- **8.2:** crear en Aiven los roles `propietario`, `app_rw` y `reporte_ro`; guardar las contraseñas en variables del proveedor o del servidor, nunca en el repo.
- **8.3:** `scripts/migrate.sh` debe conectarse con el rol propietario y `sslmode=require`.
- **8.5:** la API se despliega en el servidor virtual con IP estática; esa IP es la única habilitada en el `ip_filter` de Aiven.
- **8.6:** el front puede ir en un hosting estático con HTTPS y CORS limitado al dominio público del front.
- **8.8:** el backup se genera con `pg_dump` y se restaura en una base nueva; en Aiven Free solo hay un backup automático, así que conviene guardar un dump propio antes de la defensa.

## Re-verificación para ejecutar 8.1 (9 de noviembre de 2026)

Se volvieron a consultar las páginas oficiales antes de ejecutar la tarea:

- La página del plan Free de Aiven (actualizada el 8/sep/2026) confirma: sin tarjeta, sin límite de tiempo, 1 CPU, 1 GB RAM, 1 GB de disco, backups, `max_connections = 20`, sin VPC, sin IP estática, sin pooling y un solo servicio de cada tipo por organización. También puede apagarse por inactividad, con aviso y posterior encendido manual.
- La página de restricción de acceso (actualizada el 12/mar/2025) confirma que el `ip_filter` se configura en **Service settings → Cloud and network → Actions → Set IP address allowlist**, que por defecto es `0.0.0.0/0` y que se puede limitar a una IP o rango CIDR.

**8.1 queda cerrada:** la decisión (Aiven Free como principal, Render Free como respaldo) y sus límites están documentados en este informe.

La instancia creada en Aiven usa **PostgreSQL 18.6**, que es la versión que el proveedor habilitó para el servicio. La simulación local se hizo con PostgreSQL 16.15; las migraciones son SQL estándar y no usan características exclusivas de 16. La ejecución real de 8.2/8.3 confirmó el mismo resultado en 18.6.

## 8.2 · Base y roles en la nube

### Procedimiento ejecutado

1. Crear en Aiven un servicio PostgreSQL Free y la base `bodegas_del_atuel`.
2. Limitar el `ip_filter` a la IP desde la que se administra (provisoria) y, en 8.5, a la IP pública del servidor de la API.
3. Guardar en `.env` (nunca en el repo): `CLOUD_DB_HOST`, `CLOUD_DB_PORT`, `CLOUD_DB_NAME`, `CLOUD_ADMIN_USER`, `CLOUD_ADMIN_PASSWORD`, `BDA_OWNER_PASSWORD`, además de `DB_PASSWORD` y `REPORTE_RO_PASSWORD`.
4. Preparar los roles y aplicar las migraciones con `./scripts/migrate.sh` (ver 8.3).
5. Asignar `LOGIN` y contraseñas con `./scripts/set_role_passwords.sh --cloud`.

### Roles

- `bda_owner`: dueño lógico de la base y de los objetos. En la nube se crea con `LOGIN` y contraseña, porque es el rol con el que se aplican las migraciones.
- `app_rw`: lectura/escritura mínima para la API; sin DDL y sin `UPDATE` ni `DELETE` de `renglon_comprobante`.
- `reporte_ro`: solo lectura de las vistas y tablas de reporte.

### Detalle de implementación: 007 se aplica como administrador

`007_roles.sql` hace `COMMENT ON ROLE bda_owner`. En PostgreSQL, comentar un rol exige `ADMIN OPTION` sobre ese rol o ser superusuario. El rol que crea a `bda_owner` es el administrador del proveedor (`avnadmin`), así que es el único que tiene esa opción; `bda_owner` no puede otorgársela a sí mismo (`GRANT bda_owner TO bda_owner` falla con "role is a member of role"). Darle `CREATEROLE` a `bda_owner` tampoco alcanza: el error pasa a "must have the ADMIN option on role bda_owner".

Por eso `migrate.sh` aplica 001–006 y 008 como `bda_owner`, y **007 como administrador**. El administrador conserva:

- membresía en `bda_owner` (necesaria para `ALTER DATABASE ... OWNER TO bda_owner` y para operar sobre objetos del dueño durante 007);
- `CONNECT` explícito sobre la base, porque 007 revoca `PUBLIC` y sin esa concesión el administrador ya no podría conectarse para asignar contraseñas.

`bda_owner` recibe `CREATEROLE` sólo durante la aplicación de 007 y el script se lo quita al terminar (incluso si falla).

### Esquema `public` en Aiven

El dueño de `public` depende del servicio. Si pertenece al usuario interno `postgres`, `avnadmin` no puede modificarlo hasta reclamarlo con `aiven_extras`:

```sql
CREATE EXTENSION IF NOT EXISTS aiven_extras CASCADE;
SELECT * FROM aiven_extras.claim_public_schema_ownership();
```

Por eso `migrate.sh` consulta el dueño de `public`. Sólo si no es `pg_database_owner`, `bda_owner` ni el administrador, y `aiven_extras` está disponible, crea la extensión y reclama el esquema. Luego ejecuta `GRANT USAGE, CREATE ON SCHEMA public TO bda_owner`. En PostgreSQL común no existe `aiven_extras`, así que sólo hace el `GRANT`. Sin ese permiso, 001 fallaría al crear tablas como `bda_owner` porque en PostgreSQL 15+ `PUBLIC` ya no tiene `CREATE` sobre `public`.

En el servicio real, `public` ya pertenece a `pg_database_owner`; por eso **no se instaló `aiven_extras`** y el esquema quedó sin objetos de proveedor. Si en otro servicio hay que reclamarlo, `public` queda owned por `avnadmin` y al comparar esquemas hay que excluir los objetos de `aiven_extras`.

### Evidencia en ejecución real (9 de noviembre de 2026)

Se ejecutó el flujo completo contra el servicio Aiven, PostgreSQL **18.6**, con `sslmode=require` y la base `bodegas_del_atuel`:

- `./scripts/migrate.sh` terminó con exit 0 y el resumen `tablas=29, vistas=4, secuencias=13, rutinas=15, triggers=10`.
- La base quedó con dueño `bda_owner`; los 29 objetos de tabla, 4 vistas, 13 secuencias y 15 rutinas quedaron owned por `bda_owner` (0 objetos con otro dueño).
- `bda_owner` quedó `LOGIN` y `NOCREATEROLE`; `app_rw` y `reporte_ro` quedaron `LOGIN` sin `CREATEROLE`.
- `./scripts/set_role_passwords.sh --cloud` terminó OK y asignó las tres contraseñas desde `.env`.
- `public` quedó owned por `pg_database_owner`; las únicas extensiones instaladas fueron `plpgsql` (sin `aiven_extras`).
- Reejecutar `./scripts/migrate.sh` abortó con exit 1 ("el esquema ya existe") y no modificó los conteos.

También se repitió el flujo en un contenedor PostgreSQL 16.15 con administrador no superusuario, para conservar una prueba reproducible sin depender de Aiven. Los valores reales de host, IP y contraseñas no se registran en este informe.

## 8.3 · Migraciones

`scripts/migrate.sh` aplica `db/migrations/*.sql` en orden:

- **Modo nube (sin argumentos):** usa `CLOUD_DB_*` y `CLOUD_ADMIN_*`. Prepara `bda_owner`, aplica las migraciones y deja la base con el mismo esquema que la local. Usa `sslmode=require` por defecto (`CLOUD_DB_SSLMODE`).
- **Modo URL (`--db-url`):** aplica todas las migraciones con el usuario de la URL. Se usa para el dry-run local contra una base scratch.

Seguridad:

- Se niega a aplicar si `public.localidad` ya existe, porque las migraciones no son idempotentes.
- No imprime contraseñas.
- El administrador se usa para crear `bda_owner`, reclamar `public` si hace falta, transferir la base y aplicar 007; el resto se aplica como `bda_owner`.

### Evidencia de paridad

Se comparó el esquema local (PostgreSQL 16.15) con el de Aiven (PostgreSQL 18.6) usando `pg_dump 18.6 --schema-only --no-owner --no-privileges --schema=public`:

- Ambos dumps tienen 2168 líneas.
- El `diff` sólo muestra el comentario de versión del servidor y el token `\restrict`/`\unrestrict` que genera cada dump; **no hay diferencias de esquema**.

### Matriz de privilegios en Aiven

Verificada con `has_*_privilege` y con denegaciones vivas:

- `app_rw`: `SELECT/INSERT/UPDATE/DELETE` en `vino`; sin `UPDATE` ni `DELETE` en `renglon_comprobante`; sin `CREATE` sobre `public`; sin `USAGE` sobre secuencias; `EXECUTE` en las 6 rutinas contratadas.
- `reporte_ro`: `SELECT` en `vw_stock_total_vino`; sin `INSERT` en `vino`; sin `EXECUTE` en las rutinas de negocio.
- Denegaciones vivas con SQLSTATE `42501`: `app_rw` al crear una tabla (`permission denied for schema public`) y al actualizar `renglon_comprobante`; `reporte_ro` al insertar en `vino`.

### Observación sobre 008

Al aplicar `008_indices.sql` como `bda_owner` (no superusuario), PostgreSQL 18 emite advertencias `permission denied to analyze "pg_..."` para catálogos del sistema (`pg_authid`, `pg_subscription`, etc.). Son advertencias del `ANALYZE` final, no errores: los índices se crean y la migración termina con exit 0.

### Estado para 8.5

La base y los roles están listos para que P3 despliegue la API:

- Conexión: `CLOUD_DB_HOST`, `CLOUD_DB_PORT`, `CLOUD_DB_NAME=bodegas_del_atuel`, `sslmode=require`.
- Rol de la API: `app_rw` con la contraseña de `DB_PASSWORD`.
- `bda_owner` es el dueño lógico; `reporte_ro` queda para reportes.
- La base está vacía: la carga de datos es la tarea 8.4 (P2).
- El plan Free tiene `max_connections = 20`; la API debe usar un pool pequeño.

**8.2 y 8.3 quedan cerradas técnicamente** contra Aiven; falta el commit/PR y la revisión correspondiente.
