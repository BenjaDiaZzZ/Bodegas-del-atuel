# Fase 1 · Modelado (H1)

> Este informe se completa entre P1 y P2. Las secciones de P1 (DER, esquema
> relacional y `001_esquema.sql`) se agregan en sus respectivas tareas. A
> continuación se documenta el aporte de P2.

## 1.4 · Catálogos en CSV (P2)

**Estado:** pendiente del Anexo B.

Los catálogos deben copiar exactamente los valores del Anexo B del enunciado.
Ese anexo todavía no está disponible en el repositorio, por lo que no se
generaron valores provisorios para no contaminar la carga con datos inventados.

Con `001_esquema.sql` ya disponible, los catálogos que alimentan tablas son:

- `cepas.csv`: `id_cepa,nombre,tipo`, para la tabla `cepa`.
- `maridajes.csv`: `id_maridaje,nombre,temperatura_servicio`, para `maridaje`.
- `localidades_mendoza.csv`: `id_localidad,codigo_postal,nombre,provincia,encargado_regional`,
  para `localidad`.

Los tipos de vino y las presentaciones se validan con `CHECK` en
`002_constraints.sql` y se usan como listas de valores para la carga, porque
`vino` guarda `tipo` y `presentacion_ml` como atributos. Todos los archivos
deberán estar en UTF-8, sin BOM, con cabecera en `snake_case` y separador coma.
La validación contra el Anexo B queda como criterio de aceptación de la tarea.

## 1.5 · Normalización a 3FN (P2)

Se reescribió `docs/normalizacion.md` tomando como fuente el esquema físico real
de `db/migrations/001_esquema.sql` (29 tablas, 29 PK y 34 FK). El documento
incluye:

- Las dependencias funcionales de las 29 relaciones.
- La demostración de 1FN: atributos atómicos, separación de renglones y tablas
  `N:M` (`composicion`, `vino_maridaje`, `transportista_localidad`,
  `renglon_comprobante`, `renglon_ingreso`, `renglon_transferencia` y
  `stock_sala`).
- La demostración de 2FN en las tablas con clave compuesta: `parcela`,
  `composicion`, `vino_maridaje`, `transportista_localidad`,
  `permiso_exportacion`, `renglon_comprobante`, `renglon_ingreso`,
  `renglon_transferencia` y `stock_sala`.
- La demostración de 3FN: localidad, provincia y encargado regional dependen
  de `localidad`; los datos de socio, distribuidor y exportador se separan en
  subtipos; bodega, cepa y maridaje se referencian por `FK`; y
  `subtotal`/`descuento`/`total` se documentan como atributos derivados
  controlados por triggers.
- La justificación de que departamento y provincia en `finca` son atributos
  descriptivos y no generan una dependencia transitiva directa.
- La observación de las claves candidatas que deben declararse `UNIQUE` en
  `002_constraints.sql`: `localidad.codigo_postal`, `transportista.cuit`,
  `vino(nombre_comercial, anada, presentacion_ml)` y
  `lote_uva(id_finca, nro_parcela, campania)`.

**Cómo verificar:** abrir `docs/normalizacion.md` y comprobar que cada relación
tiene sus dependencias funcionales listadas y que las secciones 3, 4 y 5
justifican 1FN, 2FN y 3FN respectivamente.

## 1.6 · Diccionario de datos (P2)

**Estado:** completado para `001_esquema.sql`.

Se levantó PostgreSQL 16.15 en Docker (puerto 5433) y se aplicó
`db/migrations/001_esquema.sql`. A partir de `information_schema` y
`pg_catalog` se generó `docs/diccionario.md` con:

- 29 tablas y 125 columnas.
- Tipo físico, nulabilidad, valor por defecto, restricciones (`PK`, `FK`,
  `UNIQUE`) y descripción funcional de cada columna.
- Resumen de tablas y consulta de verificación.

**Cómo verificar:**

```bash
docker compose exec db psql -U bodegas -d bodegas_del_atuel \
  -tAc "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public';"
```

El resultado debe ser `125`, que coincide con las filas del diccionario.

> `001_esquema.sql` solo define tipos, tablas, PK y FK. Cuando P1 agregue
> `002_constraints.sql` con los `CHECK`, `UNIQUE`, `DEFAULT` y `NOT NULL`, el
> diccionario deberá regenerarse para reflejar el esquema completo.
