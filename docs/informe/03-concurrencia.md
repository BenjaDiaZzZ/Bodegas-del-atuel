# Demostración de concurrencia (Tarea 2.9)

## Objetivo

Demostrar, bajo el nivel de aislamiento por defecto de PostgreSQL
(`READ COMMITTED`), por qué la venta de la última botella necesita un
`SELECT ... FOR UPDATE` y cómo el trigger de RN-09 evita el *lost update*.
Como complemento se incluye la prueba de concurrencia de transferencias, que
verifica RN-12 y la atomicidad de `sp_procesar_transferencia`.

## Entorno

- PostgreSQL 16 (`postgres:16-alpine`), base descartable.
- Migraciones aplicadas en orden: `001_esquema.sql` a `005_triggers.sql`.
- Nivel de aislamiento: `READ COMMITTED` (el default).
- Datos: sala 1, cliente socio con 10 % de descuento, un vino por escenario y
  `stock_sala.cantidad = 1`.
- Dos procesos `psql` independientes, identificados con `PGAPPNAME=conc_A` y
  `PGAPPNAME=conc_B`, y marcas de tiempo con `clock_timestamp()`.

## Escenario 1 · Sin `FOR UPDATE`: lost update

Se simula la lógica de aplicación que lee el stock, calcula el nuevo valor y
escribe ese valor calculado. No se usa el trigger de venta en este escenario:

1. Sesión A: `BEGIN; SELECT cantidad ...;` obtiene `1` y espera 3 segundos.
2. Sesión B: `BEGIN; SELECT cantidad ...;` también obtiene `1`, calcula
   `1 - 1 = 0` y hace `UPDATE stock_sala SET cantidad = 0; COMMIT;`.
3. Sesión A: continúa, escribe el valor que calculó (`1 - 1 = 0`) y hace
   `COMMIT;`.

Salida real:

```text
A leyo a las '2026-11-07 22:19:11.228974+00' stock= '1'
B leyo a las '2026-11-07 22:19:11.808714+00' stock= '1'

          ts_b_update
-------------------------------
 2026-11-07 22:19:11.812668+00

          ts_a_update
-------------------------------
 2026-11-07 22:19:14.241714+00

stock final escenario 1: 0
```

Ambas sesiones leyeron `1` y ambas confirmaron una venta, pero el stock final
quedó en `0`: se vendieron dos botellas cuando había una sola. La segunda
escritura pisó a la primera; ese es el *lost update*.

El `CHECK (cantidad >= 0)` no alcanza para detectar este caso porque el valor
final es `0`, no negativo. Un `UPDATE stock_sala SET cantidad = cantidad - 1`
tampoco reproduce la anomalía, porque PostgreSQL serializa la escritura sobre la
misma fila. El problema aparece cuando la lectura y la escritura se separan en
el tiempo, que es exactamente lo que ocurre entre la validación de stock y el
descuento en una venta.

## Escenario 2 · Con `SELECT ... FOR UPDATE`: RN-09

Ahora se usan los triggers reales de `005_triggers.sql`. El trigger
`fn_tg_renglon_venta_completar` (BEFORE INSERT de `renglon_comprobante`) hace:

```sql
SELECT cantidad
  INTO v_disponible
  FROM stock_sala
 WHERE id_sala = v_sala
   AND cod_vino = NEW.cod_vino
   FOR UPDATE;
```

Secuencia:

1. Sesión A: `BEGIN`, inserta un `comprobante` y un `renglon_comprobante` por
   una botella. El trigger toma el lock de la fila de `stock_sala`, valida `1`,
   completa la línea y el trigger AFTER descuenta el stock a `0`. A duerme 4
   segundos antes del `COMMIT`.
2. Sesión B: intenta insertar otro `comprobante` y otro renglón para el mismo
   vino. El trigger intenta el mismo `FOR UPDATE` y queda bloqueado.
3. Sesión A hace `COMMIT`. B se desbloquea, vuelve a leer la fila ya confirmada
   (`0`) y el trigger lanza la excepción de negocio.

Salida real:

```text
NOTICE:  A inserto el renglon y tomo el lock a las 2026-11-07 22:19:14.563522+00

ERROR:  [RN-09] Stock insuficiente del vino 2 en la sala 1: disponible 0, solicitado 1
CONTEXTO:  PL/pgSQL function fn_tg_renglon_venta_completar() line 32 at RAISE

stock final escenario 2: 0
renglones: 1
```

Resultado: solo se registró una venta. La segunda sesión no pudo confirmar su
renglón y su transacción se revirtió. El lock se mantiene hasta el `COMMIT`, por
eso la validación y el descuento son atómicos para esa fila.

## Escenario 3 · Transferencia y RN-12

La prueba `db/tests/test_004_concurrency.sh` cubre el caso de
`sp_procesar_transferencia`:

1. La sesión C bloquea la fila de `stock_deposito` del vino A y la mantiene
   tomada.
2. La sesión A ejecuta `CALL sp_procesar_transferencia(...)` y queda esperando
   el lock del depósito.
3. La sesión B intenta editar la cantidad del renglón de una transferencia ya
   `terminada`. El trigger de RN-12 la rechaza con `[RN-12]`.
4. C libera el lock; A procesa exactamente el conjunto que validó.

Salida real:

```text
nro_solicitud=1 vino_A=1
sesion A bloqueada en un lock
RN-12 rechazo la edicion concurrente: OK
stock_deposito=90 stock_sala=10 estado=procesado (esperado: 90 / 10 / procesado)
OK: RN-12 bloqueo la edicion y el procedimiento consumio el conjunto que valido (10)
```

Esto complementa la demostración de venta: el documento terminado congela sus
renglones y el procedimiento mueve stock de forma consistente aunque otra sesión
intente modificarlo en paralelo.

## Resultados

| Escenario | Mecanismo | Resultado |
|---|---|---|
| 1 · Venta sin lock | Lectura y escritura separadas | Dos ventas, stock final `0` (*lost update*) |
| 2 · Venta con RN-09 | `SELECT ... FOR UPDATE` en el trigger | Una venta, segunda rechazada con `[RN-09]` |
| 3 · Transferencia con RN-12 | Lock de stock + bloqueo de renglones | `90 / 10 / procesado`, edición concurrente rechazada |

## Reproducción

Para el escenario de transferencia, con una base descartable y las migraciones
`001` a `005` aplicadas:

```bash
PGHOST=localhost PGPORT=5433 PGUSER=bodegas PGDATABASE=<db_temporal> \
  ./db/tests/test_004_concurrency.sh
```

Para los escenarios de venta se usaron dos procesos `psql` con las siguientes
operaciones base. El escenario 1 omite el trigger y escribe el valor calculado;
el escenario 2 usa los triggers reales e inserta `comprobante` +
`renglon_comprobante` en cada sesión.

```sql
-- Escenario 1, sesion A (B hace lo mismo sin el pg_sleep)
BEGIN;
SELECT clock_timestamp(), cantidad
  FROM stock_sala WHERE id_sala = 1 AND cod_vino = <vino> \gset
SELECT pg_sleep(3);
UPDATE stock_sala SET cantidad = :cantidad - 1
 WHERE id_sala = 1 AND cod_vino = <vino>;
COMMIT;

-- Escenario 2, sesion A (B repite el INSERT y queda bloqueada)
BEGIN;
INSERT INTO comprobante (id_cliente, id_sala)
VALUES (<cliente>, 1)
RETURNING nro_comprobante AS nro \gset
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
VALUES (:'nro', <vino>, 1);
SELECT pg_sleep(4);
COMMIT;
```

La diferencia entre ambos escenarios es el `FOR UPDATE` del trigger: sin él, la
segunda sesión puede confirmar una venta sobre stock que ya no existe; con él,
la segunda espera, relee el valor confirmado y falla con `[RN-09]`.
