# Índices y rendimiento (Fase 4 · Tareas 4.1–4.6)

## Entorno de medición

- PostgreSQL 16, base temporal con migraciones `001`–`008`.
- Dataset `--scale full`: **350.000** `renglon_comprobante`, **20.000** `comprobante`, **306** `vino`, **200** `cliente`.
- `ANALYZE` ejecutado antes de cada ronda de mediciones.
- Consultas de referencia: `S1`, `S4`, `S8`, `S10` de `consultas/select.sql`.

## 4.1 · Medición «Antes» (solo PKs y UNIQUEs)

| Consulta | Execution Time (ms) | Plan principal | Buffers |
|---|---:|---|---|
| S1 · Ventas por sala y mes | 4.946 | Seq Scan `renglon_comprobante` + `comprobante`, Sort en disco (15 MB) | — |
| S4 · Ranking vinos más vendidos | 555 | Parallel Seq Scan `renglon_comprobante` | — |
| S8 · Stock por sala con faltantes | 2,4 | Seq Scan `stock_sala` (200 filas) | — |
| S10 · Clientes sobre promedio (CTE) | 4.175 | Seq Scan `comprobante` + `cliente`, subconsulta correlacionada | — |

## 4.2 · Diseño de `008_indices.sql`

Se crean **7 índices** cubriendo los 6 tipos pedidos:

| # | Tipo | Índice | Justificación |
|---|---|---|---|
| 1 | **Compuesto** | `idx_comprobante_sala_fecha ON comprobante (id_sala, fecha)` | S1 agrupa por sala y rango de fechas. Orden: igualdad primero, rango después. |
| 2 | **Parcial** | `idx_transferencia_no_procesadas ON transferencia (id_sala, fecha_confeccion) WHERE estado <> 'procesado'` | La mayoría de transferencias están procesadas; el filtro selectivo reduce el índice. |
| 3 | **FK no-PK + INCLUDE** | `idx_renglon_comprobante_vino ON renglon_comprobante (cod_vino) INCLUDE (cantidad, subtotal, descuento)` | PostgreSQL no indexa el lado hijo de FK. INCLUDE habilita Index-Only Scan para S4. |
| 3b | **FK no-PK** | `idx_renglon_comprobante_nro ON renglon_comprobante (nro_comprobante)` | Acelera el JOIN de S1 con comprobante. |
| 4 | **Covering INCLUDE** | `idx_comprobante_cliente_total ON comprobante (id_cliente, fecha) INCLUDE (total)` | S10 agrega `SUM(total)` por cliente; INCLUDE evita acceso al heap. |
| 5 | **BRIN** | `idx_comprobante_fecha_brin ON comprobante USING brin (fecha)` | Fechas correlacionadas con inserción; BRIN es compacto para rangos. |
| 6 | **Covering** | `idx_stock_sala_sala_cantidad ON stock_sala (id_sala, cantidad) INCLUDE (cod_vino)` | S8 filtra `cantidad = 0` y agrupa por sala. |

## 4.3 · Medición «Después» — Tabla comparativa

| Consulta | Tiempo Antes (ms) | Tiempo Después (ms) | Δ | Plan Antes | Plan Después | Observación |
|---|---:|---:|---|---|---|---|
| S1 | 4.946 | 3.332 | **−33%** | Seq Scan + Sort disco | Seq Scan + Sort disco | Mejora por join más eficiente, pero Sort sigue en disco |
| S4 | 555 | 1.066 | +92% | Parallel Seq Scan | Parallel Seq Scan | Índice no elegido — ver 4.6 |
| S8 | 2,4 | 2,6 | +8% | Seq Scan (200 filas) | Seq Scan (200 filas) | Tabla demasiado pequeña para beneficiarse |
| S10 | 4.175 | 4.594 | +10% | Seq Scan + correlacionada | Seq Scan + correlacionada | El cuello de botella es la subconsulta correlacionada |

**Conclusión:** los índices mejoran S1 (33%) pero S4 y S10 no se benefician porque el planificador elige `Seq Scan` para escaneos completos de tabla (350k filas), que es más eficiente que `Index Scan` cuando se leen todas las filas.

## 4.4 · Orden de columnas e índice descartado

**Orden del índice compuesto #1** `(id_sala, fecha)`:

- `id_sala` primero: igualdad (`WHERE id_sala = X`) → permite bseek directo.
- `fecha` después: rango (`WHERE fecha BETWEEN a AND b`) → se aprovecha el orden dentro de cada sala.
- Si el orden fuera `(fecha, id_sala)`, una consulta `WHERE id_sala = X AND fecha > Y` no podría usar el índice eficientemente porque `id_sala` no está en la posición de búsqueda.

**Índice descartado:** `idx_comprobante_descuento ON comprobante (descuento)` — se evaluó porque S1 agrega `SUM(rc.descuento)`, pero `descuento` vive en `renglon_comprobante`, no en `comprobante`. Un índice sobre `comprobante.descuento` no ayudaría y aumentaría el costo de escritura sin beneficio de lectura.

## 4.5 · Costo de escritura

Se midió la inserción de 5.000 filas en `renglon_comprobante` con y sin los índices secundarios:

| Escenario | Tiempo | Overhead |
|---|---:|---|
| Sin índices secundarios (solo PK) | 0,032 s | — |
| Con 7 índices secundarios | 0,089 s | +178% |

**Análisis:** cada INSERT debe actualizar los 7 índices. El overhead es aceptable para carga masiva (se desactivan índices o se usa COPY) pero relevante para INSERTs transaccionales. Para volúmenes altos, la estrategia es: cargar sin índices secundarios → crear índices → `ANALYZE`.

## 4.6 · Índice existe pero el planificador elige Seq Scan

**Caso: S4 (ranking de vinos más vendidos)**

```sql
SELECT v.cod_vino, SUM(rc.cantidad) ...
  FROM renglon_comprobante rc
  JOIN vino v ON v.cod_vino = rc.cod_vino
 GROUP BY v.cod_vino ...
```

El índice `idx_renglon_comprobante_vino` existe sobre `(cod_vino) INCLUDE (cantidad, subtotal, descuento)`, pero el planificador elige `Parallel Seq Scan`:

```
->  Parallel Seq Scan on renglon_comprobante rc
    (cost=0.00..5002.82 rows=205882 width=16)
    (actual time=0.047..150.346 rows=175000 loops=2)
```

**¿Por qué?** La consulta agrega **todas** las filas de `renglon_comprobante` (350.000). Cuando se leen más del ~20% de las filas de una tabla, `Seq Scan` es más eficiente que `Index Scan` porque evita el overhead de buscar cada fila individualmente en el índice y luego en el heap. El índice solo sería útil si la consulta filtrara un subconjunto pequeño (por ejemplo `WHERE cod_vino = X`).

**Verificación con filtro selectivo** (el índice SÍ se usa):

```sql
EXPLAIN SELECT * FROM renglon_comprobante WHERE cod_vino = 5;
-- Index Scan usando idx_renglon_comprobante_vino
```

Esto demuestra que el índice funciona correctamente, pero el planificador lo descarta cuando la selectividad es baja (full scan).
