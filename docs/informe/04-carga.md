# Carga masiva determinística (Fase 3 · Tareas 3.1–3.7)

## 3.1 · Orden de carga

El orden sigue la topología de claves foráneas. Los catálogos CSV se cargan
primero porque no tienen dependencias; luego las entidades independientes y
finalmente las dependientes. El diagrama completo está en
[`db/seed/README.md`](../db/seed/README.md).

```mermaid
graph TD
    CSV1[CSV: cepas] --> cepa
    CSV2[CSV: maridajes] --> maridaje
    CSV3[CSV: localidades] --> localidad
    localidad --> sala
    localidad --> cliente
    bodega --> vino
    bodega --> lote_uva
    bodega --> ingreso
    transportista --> ingreso
    finca --> parcela
    finca --> lote_uva
    cepa --> parcela
    cepa --> composicion
    sala --> empleado
    sala --> comprobante
    sala --> transferencia
    sala --> stock_sala
    parcela --> lote_uva
    vino --> composicion
    vino --> vino_maridaje
    vino --> renglon_comprobante
    vino --> renglon_ingreso
    vino --> renglon_transferencia
    vino --> stock_deposito
    vino --> stock_sala
    cliente --> comprobante
    cliente --> socio
    cliente --> distribuidor
    cliente --> exportador
    exportador --> permiso_exportacion
    lote_uva --> analisis_calidad
    comprobante --> renglon_comprobante
    ingreso --> renglon_ingreso
    transferencia --> renglon_transferencia
```

## 3.2 · Determinismo y CLI

- `random.seed(42)` y `Faker.seed(42)` al inicio de cada corrida.
- `--scale small` produce ~28 tablas con datos mínimos (50 comprobantes, 151 renglones).
- `--scale full` produce 20.000 comprobantes y ~350.000 renglones.
- `--fecha-base YYYY-MM-DD` define la fecha de referencia para datos históricos.
- Todas las fechas se calculan relativas a `fecha_base`, nunca como valores absolutos.

## 3.3 · Sembrado dirigido para la Sección 8

| Consulta | Qué se siembra |
|---|---|
| D1 | Comprobantes de socios con `fecha_alta > 5 años` |
| D4/D6 | Socios sin compra, alta > 5 años, localidad específica |
| U2/D3 | Empleados con > 5 años y < 5 años de antigüedad |
| U4 | Salas con `dia_cierre_semanal = 1` (Lunes) y `= 3` (Miércoles) |
| U6 | Exportadores con 4+ permisos de exportación |
| I1 | Localidad 'General Alvear' en el CSV; transportista con menos ingresos |
| I2 | Vinos tintos con `graduacion ≥ 14` |
| I6 | Vino 'Malbec Reserva' de presentación 750 ml |
| D5 | Ingresos en estado `'procesado'` con `fecha > 365 días` |
| RN-05 | Todas las composiciones suman exactamente `100.00` |

## 3.4 · Estrategia frente a triggers

Los triggers de `005_triggers.sql` (RN-08, RN-09, RN-10, RN-11, RN-12)
validan y calculan al insertar. Para la carga histórica se desactivan:

```sql
ALTER TABLE renglon_comprobante   DISABLE TRIGGER USER;
ALTER TABLE comprobante            DISABLE TRIGGER USER;
ALTER TABLE ingreso               DISABLE TRIGGER USER;
ALTER TABLE transferencia          DISABLE TRIGGER USER;
ALTER TABLE renglon_ingreso        DISABLE TRIGGER USER;
ALTER TABLE renglon_transferencia  DISABLE TRIGGER USER;
```

**Ventajas:** carga rápida sin validación por fila; se insertan datos
históricos con estados `procesado`/`terminado` que los triggers rechazarían.

**Riesgos:** los triggers no validan durante la carga. Se compensa con
`db/seed/controles.sql`, que verifica integridad referencial, stocks no
negativos, composiciones = 100 % y totales de comprobante consistentes.

Al finalizar se recalculan los totales con un solo `UPDATE` por conjuntos y se
reactivan los triggers con `ENABLE TRIGGER USER`.

## 3.5 · Protocolo COPY y Benchmark

Se usa `psycopg3.copy()`:

```python
with cur.copy("COPY tabla (col1, col2) FROM STDIN") as copy:
    for row in rows:
        copy.write_row(row)
```

Para `vino` se usa `INSERT ... RETURNING` porque `cod_vino` es
`GENERATED ALWAYS AS IDENTITY` y COPY no permite override.

### Resultado del benchmark (5.000 filas)

| Método | Tiempo | Speedup |
|---|---|---|
| INSERT fila por fila | 3,972 s | 1x |
| COPY por lotes | 0,032 s | **125,9x** |

Reproducir con:

```bash
python3 db/seed/seed.py --benchmark
```

## 3.6 · Consultas de control

`db/seed/controles.sql` verifica:

1. Conteo por tabla (28 tablas).
2. 0 filas huérfanas (FK no resueltas).
3. 0 stocks negativos.
4. 0 comprobantes con `total ≠ SUM(subtotal)` de sus renglones.
5. 0 vinos con composición ≠ 100.
6. 0 estados inválidos en `ingreso` y `transferencia`.

## 3.7 · Script y dump

```bash
scripts/seed.sh --scale small --fecha-base 2026-01-01
```

El script ejecuta `seed.py` y luego `controles.sql`. El dump del dataset
completo se genera con `pg_dump` después de la carga:

```bash
pg_dump --data-only --no-owner bodegas_del_atuel > seed_dump.sql
```
