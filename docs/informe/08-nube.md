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
