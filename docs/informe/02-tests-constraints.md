# Pruebas de constraints · `db/tests/db_tests.sql`

## Qué prueba

Valida una muestra representativa de las restricciones agregadas en `db/migrations/002_constraints.sql` sobre el esquema de `001_esquema.sql`: UNIQUE, CHECK (incluido uno cruzado entre columnas) y DEFAULT. No reemplaza a los tests de reglas de negocio (`RN-xx`), que se resuelven con triggers en fases posteriores.

## Cómo se ejecuta

Como en clase se nos hizo ejecutar postgres en un contenedor de docker el siguiente comando solo sirve si postgres esta ejecutandose en un contenedor de docker

```bash
docker exec -i {nombre_del_servicio} psql -U postgres -d {nombre_de_la_db} < db/tests/db_tests.sql
```

## Cómo está armado

1. **Sección 0 — datos base.** Inserta bodega, localidad, finca, cepa, sala, clientes, exportador y transportista, y termina con `COMMIT`. Las pruebas siguientes referencian esas filas, por eso no puede revertirse. `ON CONFLICT DO NOTHING` permite correr el script varias veces.
2. **Casos válidos.** Van dentro de `DO $$ ... $$`: insertan el dato, verifican que la base lo acepte y lo eliminan. `RAISE NOTICE` solo existe en PL/pgSQL, por eso no se puede usar en SQL plano.
3. **Casos inválidos.** También dentro de `DO $$ ... $$`: esperan el SQLSTATE de la restricción. Si la operación no falla, `RAISE EXCEPTION` aborta la prueba y queda marcada como FAIL.
4. **Atomicidad.** Cada bloque `DO` es una subtransacción: si el `INSERT` falla, ese bloque se revierte completo y no deja datos a medias.

## Resultados

Verificado sobre PostgreSQL 16. Dos corridas consecutivas terminan con `EXIT=0`.

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

## Por qué dan esos resultados

- **Casos válidos:** el valor cumple el CHECK o UNIQUE, el `INSERT` no lanza excepción y el bloque imprime `OK`.
- **Casos inválidos:** la restricción lanza `23514` (`check_violation`) o `23505` (`unique_violation`), el `EXCEPTION` del bloque lo captura e imprime `OK`. Si el dato hubiera sido aceptado, el `RAISE EXCEPTION` haría fallar la prueba.
- **UNIQUE 5 y 6:** el primer registro se confirma para que el duplicado choque de verdad. En la versión anterior el primer `INSERT` se revertía y el duplicado nunca colisionaba.
- **DEFAULT (8):** se verifica el valor devuelto por `RETURNING`, no solo que el `INSERT` no falle.
- **IDs:** `cod_vino` e `ingreso.cod_ingreso` son `IDENTITY`; se capturan con `RETURNING` en lugar de asumir 1 o 2.
- **Exportador (3):** se usa un cliente dedicado con `tipo = 'exportador'`, porque la FK compuesta `(id_cliente, tipo)` exige que el tipo coincida.

