# Índices y rendimiento (Fase 4 · Tareas 4.1–4.7)

## Entorno de medición

- PostgreSQL 16, base temporal con migraciones `001`–`008`.
- Dataset `--scale full`: **350.000** `renglon_comprobante`, **20.000** `comprobante`, **306** `vino`, **200** `cliente`.
- `ANALYZE` ejecutado antes de cada ronda de mediciones.
- Consultas de referencia: `S1`, `S4`, `S8`, `S10` de `consultas/select.sql`.

## 4.1 · Medición «Antes» (solo PKs y UNIQUEs)

Los valores de esta tabla corresponden a la corrida original de su autor, en su propio entorno; no fueron reproducidos en la verificación independiente de §4.7. Se conservan como evidencia del reporte original, no como resultados confirmados.

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
| 1 | **Compuesto** | `idx_comprobante_sala_fecha ON comprobante (id_sala, fecha)` | El orden propuesto pone `id_sala` antes de `fecha`, pero la S1 publicada no tiene `WHERE`, igualdad por sala ni rango de fechas: agrupa y ordena todas las ventas por sala y mes. Por lo tanto, la justificación de igualdad primero y rango después no corresponde a la consulta entregada; la utilidad del índice para S1 requiere otra consulta o medición específica. |
| 2 | **Parcial** | `idx_transferencia_no_procesadas ON transferencia (id_sala, fecha_confeccion) WHERE estado <> 'procesado'` | `estado` es `estado_documento` (`en_confeccion`, `terminado`, `procesado`); el seed genera los tres valores. El predicado incluye las transferencias no procesadas y excluye las procesadas. |
| 3 | **FK no-PK + INCLUDE** | `idx_renglon_comprobante_vino ON renglon_comprobante (cod_vino) INCLUDE (cantidad, subtotal, descuento)` | PostgreSQL no indexa el lado hijo de FK. INCLUDE habilita Index-Only Scan para S4. |
| 3b | **FK no-PK** | `idx_renglon_comprobante_nro ON renglon_comprobante (nro_comprobante)` | Acelera el JOIN de S1 con comprobante. |
| 4 | **Covering INCLUDE** | `idx_comprobante_cliente_total ON comprobante (id_cliente, fecha) INCLUDE (total)` | S10 agrega `SUM(total)` por cliente; INCLUDE evita acceso al heap. |
| 5 | **BRIN** | `idx_comprobante_fecha_brin ON comprobante USING brin (fecha)` | El seed asigna fechas aleatorias dentro de una ventana de seis años (salvo cinco comprobantes especiales); no garantiza correlación con el orden de inserción. La eficacia de BRIN para estos datos debe medirse, no inferirse por correlación. |
| 6 | **Covering** | `idx_stock_sala_sala_cantidad ON stock_sala (id_sala, cantidad) INCLUDE (cod_vino)` | S8 agrega y agrupa por sala y calcula un filtro agregado por `cantidad = 0`; el DDL incluye `cod_vino` pero no cubre todas las columnas/proyecciones de S8. La tabla tiene sólo 200 filas, por lo que hay que confirmar el plan observado; no se debe afirmar un Index-Only Scan sin EXPLAIN. |

## 4.3 · Medición «Después» — Tabla comparativa

Los tiempos y planes de las tablas §4.1 y §4.3 son los de la corrida original de su autor y su entorno; no fueron reproducidos aquí. La comprobación independiente está en §4.7, que conserva ambos conjuntos de valores y explicita sus diferencias.

| Consulta | Tiempo Antes (ms) | Tiempo Después (ms) | Δ | Plan Antes | Plan Después | Observación |
|---|---:|---:|---|---|---|---|
| S1 | 4.946 | 3.332 | **−33% (reporte original)** | Seq Scan + Sort disco | Seq Scan + Sort disco | Mejora reportada originalmente; no reproducida en §4.7 |
| S4 | 555 | 1.066 | +92% | Parallel Seq Scan | Parallel Seq Scan | Índice no elegido — ver 4.6 |
| S8 | 2,4 | 2,6 | +8% | Seq Scan (200 filas) | Seq Scan (200 filas) | Tabla demasiado pequeña para beneficiarse |
| S10 | 4.175 | 4.594 | +10% | Seq Scan + correlacionada | Seq Scan + correlacionada | El cuello de botella es la subconsulta correlacionada |

**Conclusión:** la mejora del 33% de S1 es un resultado de la corrida original y no se reprodujo: en la corrida documentada en §4.7 S1 empeoró levemente (488,426 → 507,588 ms; +3,9%). No corresponde afirmar que los índices mejoran S1 con la evidencia disponible. La corrida original también reportó aumentos para S4 y S10; §4.7 presenta los resultados reproducidos y sus límites.

## 4.4 · Orden de columnas e índice descartado

**Orden del índice compuesto #1** `(id_sala, fecha)`: en el esquema, `id_sala` es `integer` y `fecha` es `date`. La regla de ubicar una igualdad antes de un rango es válida para una consulta que tenga esos predicados, pero no describe la S1 publicada: esta no contiene `WHERE`, agrupa por `s.id_sala` y `date_trunc('month', c.fecha)` y ordena por `s.id_sala, mes`. Así, el orden `(id_sala, fecha)` queda documentado como diseño propuesto, no como una justificación que coincida con los filtros reales de S1.

**Índice descartado:** `idx_comprobante_descuento ON comprobante (descuento)`. La premisa de que `comprobante` no tiene esa columna sería incorrecta: el esquema define `comprobante.descuento` y también `renglon_comprobante.descuento`. Sin embargo, S1 suma específicamente `rc.descuento` y no filtra por ninguna de esas columnas; por ello, un índice sobre `comprobante.descuento` no acelera esa expresión ni tiene una justificación de búsqueda en la consulta publicada, y agregaría costo de escritura.

## 4.5 · Costo de escritura

Se midió la inserción de 5.000 filas en `renglon_comprobante` con y sin los índices secundarios:

| Escenario | Tiempo | Overhead |
|---|---:|---|
| Sin índices secundarios (solo PK) | 0,032 s | — |
| Con 7 índices secundarios (reporte original) | 0,089 s | +178% |

**Análisis:** cada INSERT actualiza los índices secundarios que existen sobre `renglon_comprobante` (en esta migración, los índices por `cod_vino` y `nro_comprobante`; no los siete índices, que pertenecen a varias tablas). El overhead medido depende del entorno y debe compararse bajo las mismas condiciones. Para volúmenes altos, la estrategia es: cargar sin índices secundarios → crear índices → `ANALYZE`.

El +178% corresponde a la corrida original del autor y no se reprodujo en magnitud: §4.7 observó +7,8%. Sí se reproduce la dirección del efecto (mayor costo con índices), no su tamaño.

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

Un plan Index Scan en esa consulta selectiva demuestra que el índice puede servir para ese filtro, pero no que sea elegido para la agregación completa.

## Verificación de reproducibilidad (4.7)

### Entorno y cardinalidades

- Ejecución: 2026-11-08, Fedora 43 (Linux x86_64, kernel 7.2.13-100.fc43).
- Servidor: PostgreSQL 16.15, `x86_64-pc-linux-musl`, Alpine Linux.
- Base efímera `bodegas_t47`, migraciones 001–007 antes del bloque «Antes» y 008 antes del bloque «Después». El seed se ejecutó con `--scale full --fecha-base 2026-01-01`.
- Conteos observados: `renglon_comprobante` 350.000; `comprobante` 20.000; `vino` 306; `cliente` 200; `stock_sala` 200; `transferencia` 500.
- Se ejecutó `ANALYZE` antes de cada ronda. Los tiempos son `Execution Time` de `EXPLAIN (ANALYZE, BUFFERS, TIMING ON, FORMAT TEXT)` y varían con el estado de caché y el host.

### Mediciones reproducidas

| Consulta | Antes observado (ms) · nodo/forma | Después observado (ms) · nodo/forma | Reportado antes → después (ms) | Veredicto sobre el reporte |
|---|---|---|---:|---|
| S1 | 488,426 · `GroupAggregate`; Seq Scan de las tablas involucradas; Sort externo, 15.768 kB en disco | 507,588 · mismo `GroupAggregate`, Seq Scans y Sort externo, 15.768 kB | 4.946 → 3.332 | **NOT REPRODUCIDA**: no hubo mejora; empeoró 3,9% (488,426 → 507,588 ms), frente a −33% reportado. La escala temporal observada también difiere. |
| S4 | 77,771 · `Limit` sobre `Gather Merge`/agregación; `Parallel Seq Scan` de `renglon_comprobante` | 120,518 · misma forma, `Parallel Seq Scan` | 555 → 1.066 | **PARTIALLY**: se reprodujo que no se elige el índice para agregar todas las filas y que el tiempo aumenta; aumentó 54,9%, no el +92% reportado, y los tiempos observados difieren en escala. |
| S8 | 0,389 · `Sort` sobre `HashAggregate`; Seq Scan de `stock_sala` (200 filas) | 0,378 · misma forma y Seq Scan de `stock_sala` | 2,4 → 2,6 | **PARTIALLY**: se reprodujo el Seq Scan de la tabla pequeña, pero el tiempo bajó 2,8% en vez de subir 8%; la escala temporal reportada no coincide. |
| S10 | 514,473 · `Sort` superior; Seq Scan de `comprobante` y `cliente`, CTE correlacionada y JIT | 562,328 · misma forma, con JIT | 4.175 → 4.594 | **PARTIALLY**: se reprodujo que la forma no cambia y el tiempo empeora; aumentó 9,3% frente al +10% reportado. Las mediciones observadas son menores en escala. |

La afirmación general de que los índices mejoran S1 queda **NOT REPRODUCIDA** en esta corrida. S4 conserva el escaneo secuencial paralelo; S8 conserva el escaneo secuencial de 200 filas; S10 conserva la forma correlacionada. No se atribuyen estos resultados a una causa concreta: los tiempos absolutos dependen del entorno y la repetición disponible no basta para establecer causalidad.

### Costo de escritura

Se intentó primero insertar candidatos sobre las filas existentes: el trigger rechazó la combinación con `[RN-09] Stock insuficiente`. Al desactivar temporalmente los triggers de usuario dentro de la transacción, la inserción aún fue rechazada por `NOT NULL` en `precio_unitario`; por eso la alternativa medida generó 5.000 pares únicos comprobante/vino inexistentes, usando valores existentes para precio y vino, completó explícitamente las seis columnas, mantuvo activas las FK y revirtió la transacción. Así se midió la escritura en la tabla sin efectos de trigger, en ambos escenarios; no equivale a una venta transaccional completa.

| Escenario | Inserción observada (`\timing`) | Reportado | Veredicto |
|---|---:|---:|---|
| Antes, sin los siete índices de 008 | 132,498 ms | 0,032 s | **NOT REPRODUCIDA** en valor absoluto |
| Después, con los siete índices de 008 | 142,841 ms | 0,089 s | **NOT REPRODUCIDA** en valor absoluto |

El incremento observado fue 10,343 ms (+7,8%), contra 57 ms (+178%) reportados: la dirección del overhead se reproduce (**PARTIALLY**), pero no su magnitud. Los dos números son una sola corrida y están sujetos a variación de entorno. La migración creó los siete índices; sobre `renglon_comprobante` hay dos índices secundarios, no siete.

### Comprobación de 4.6 e idempotencia

En la medición posterior, S4 usó `Parallel Seq Scan on renglon_comprobante`, no `idx_renglon_comprobante_vino`. Para `EXPLAIN SELECT * FROM renglon_comprobante WHERE cod_vino = 5`, el plan fue `Bitmap Heap Scan` con `Bitmap Index Scan on idx_renglon_comprobante_vino`: el índice se utilizó, aunque no como el `Index Scan` simple descrito originalmente. **PARTIALLY** reproducida: se confirma el contraste entre agregación completa y filtro selectivo, con forma distinta para este último. La consulta a `pg_indexes` confirmó los siete índices. Aplicar `008_indices.sql` por segunda vez terminó sin error y mostró los índices existentes como omitidos por `IF NOT EXISTS` (**REPRODUCIDA**, idempotencia).

El generador asigna fechas aleatorias dentro de una ventana de seis años (salvo cinco comprobantes especiales), por lo que no garantiza correlación entre fecha y orden de inserción; la justificación causal de correlación de BRIN no se verifica con esta ejecución.
