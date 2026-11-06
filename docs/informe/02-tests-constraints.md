# Pruebas de constraints · `db/tests/db_tests.sql`

## Qué prueba

Valida 11 casos sobre las restricciones agregadas en
`db/migrations/002_constraints.sql` sobre el esquema de `001_esquema.sql`:
UNIQUE, CHECK (incluidos dos cruzados entre columnas), DEFAULT, la semántica de
importes del descuento, la jerarquía de clientes y el formato del código postal.
No reemplaza a los tests de reglas de negocio (`RN-xx`), que se resuelven con
triggers en fases posteriores.

## Cómo se ejecuta

La forma reproducible es levantar un PostgreSQL 16 descartable y aplicarle las
migraciones en orden:

```bash
docker run --rm -d --name bodegas_test_pg \
  -e POSTGRES_PASSWORD=test -e POSTGRES_USER=test -e POSTGRES_DB=test \
  postgres:16-alpine

docker exec -i bodegas_test_pg psql -U test -d test -v ON_ERROR_STOP=1 \
  < db/migrations/001_esquema.sql
docker exec -i bodegas_test_pg psql -U test -d test -v ON_ERROR_STOP=1 \
  < db/migrations/002_constraints.sql
docker exec -i bodegas_test_pg psql -U test -d test -v ON_ERROR_STOP=1 \
  < db/tests/db_tests.sql

docker rm -f bodegas_test_pg
```

Si PostgreSQL ya corre en un contenedor, alcanza con:

```bash
docker exec -i {nombre_del_servicio} psql -U postgres -d {nombre_de_la_db} \
  < db/tests/db_tests.sql
```

## Cómo está armado

1. **Sección 0 — datos base.** Inserta bodega, localidad, finca, cepa, sala,
   clientes, exportador y transportista, y termina con `COMMIT`. Las pruebas
   siguientes referencian esas filas, por eso no puede revertirse.
   `ON CONFLICT DO NOTHING` permite correr el script varias veces.
2. **Casos válidos.** Van dentro de `DO $$ ... $$`: insertan el dato, verifican
   que la base lo acepte y lo eliminan. `RAISE NOTICE` solo existe en PL/pgSQL,
   por eso no se puede usar en SQL plano.
3. **Casos inválidos.** También dentro de `DO $$ ... $$`: esperan el SQLSTATE de
   la restricción. Si la operación no falla, `RAISE EXCEPTION` aborta la prueba
   y queda marcada como FAIL.
4. **Atomicidad.** Cada bloque `DO` es una subtransacción: si el `INSERT` falla,
   ese bloque se revierte completo y no deja datos a medias.

## Resultados

Verificado sobre PostgreSQL 16. Dos corridas consecutivas terminan con
`EXIT=0`.

| # | Caso | Restricción | Esperado | Resultado |
|---|------|-------------|----------|-----------|
| 1 | Graduación 14 / 25 | `ck_vino_graduacion` | acepta / `23514` | OK |
| 2 | Precio 1000 / 0 | `ck_vino_precio_venta` | acepta / `23514` | OK |
| 3 | Vencimiento posterior / anterior a emisión | `ck_permiso_fechas` (cruzado) | acepta / `23514` | OK |
| 4 | Total 900 / 950 con subtotal 1000 y descuento 100 | `ck_comprobante_total` (cruzado) | acepta / `23514` | OK |
| 5 | Vino nuevo / duplicado | `uq_vino_nombre_anada_presentacion` | acepta / `23505` | OK |
| 6 | Cliente nuevo / documento duplicado | `uq_cliente_tipo_nro_documento` | acepta / `23505` | OK |
| 7 | Stock 0 / −5 | `ck_stock_sala_cantidad` | acepta / `23514` | OK |
| 8 | Ingreso sin estado explícito | `DEFAULT 'en_confeccion'` | estado `en_confeccion` | OK |
| 9 | Descuento de renglón 150.00 / −1.00 | `ck_renglon_comprobante_descuento` | acepta / `23514` | OK |
| 10 | Cambio de `cliente.tipo` con / sin subtipo | `fk_*_cliente` con `ON UPDATE RESTRICT` | `23503` / acepta | OK |
| 11 | Código postal `5600` / `55` | `ck_localidad_codigo_postal` | acepta / `23514` | OK |

## Por qué dan esos resultados

- **Casos válidos:** el valor cumple el CHECK o UNIQUE, el `INSERT` no lanza
  excepción y el bloque imprime `OK`.
- **Casos inválidos:** la restricción lanza `23514` (`check_violation`),
  `23505` (`unique_violation`) o `23503` (`foreign_key_violation`); el
  `EXCEPTION` del bloque lo captura e imprime `OK`. Si el dato hubiera sido
  aceptado, el `RAISE EXCEPTION` haría fallar la prueba.
- **UNIQUE 5 y 6:** el primer registro se confirma para que el duplicado choque
  de verdad. En la versión anterior el primer `INSERT` se revertía y el
  duplicado nunca colisionaba.
- **DEFAULT (8):** se verifica el valor devuelto por `RETURNING`, no solo que el
  `INSERT` no falle.
- **Descuento (9):** `renglon_comprobante.descuento` es un importe, no un
  porcentaje. El caso válido usa `150.00`, que antes era rechazado por el
  `BETWEEN 0 AND 100`; el inválido usa `-1.00`.
- **Jerarquía (10):** el cliente 2 tiene fila en `exportador`; cambiar su `tipo`
  a `socio` viola la FK compuesta con `ON UPDATE RESTRICT` (`23503`). Un cliente
  sin fila de subtipo sí puede cambiar de tipo.
- **Código postal (11):** `5600` cumple `^[0-9]{4}$`; `55` no lo cumple.
- **IDs:** `cod_vino` e `ingreso.cod_ingreso` son `IDENTITY`; se capturan con
  `RETURNING` en lugar de asumir 1 o 2.
- **Exportador (3):** se usa un cliente dedicado con `tipo = 'exportador'`,
  porque la FK compuesta `(id_cliente, tipo)` exige que el tipo coincida.

## Trazabilidad de la tarea 2.1

| Requisito de la consigna | Restricción / mecanismo | Caso |
|---|---|---|
| 4 UNIQUE adicionales | 10 `uq_*` (vino, lote, cliente, localidad, etc.) | 5, 6 |
| 8 CHECK | 38 CHECK (37 de tabla + 1 de dominio) | 1, 2, 3, 4, 7, 9, 11 |
| Al menos 1 CHECK cruzado | `ck_permiso_fechas`, `ck_comprobante_total` | 3, 4 |
| 3 DEFAULT | 12 DEFAULT (estados, fechas, importes, cantidades) | 8 |
| Sin `CURRENT_DATE` en CHECK | Ningún CHECK usa funciones no determinísticas | Verificación estática |
| Jerarquía de clientes coherente | FK compuesta `(id_cliente, tipo)` + `ON UPDATE RESTRICT` | 10 |
| Integridad de datos geográficos | `ck_localidad_codigo_postal` | 11 |
