# Fase 1 · Modelado (H1)

> Este informe se completa entre P1 y P2. Las secciones de P1 (DER, esquema
> relacional y `001_esquema.sql`) se agregan en sus respectivas tareas. A
> continuación se documenta el aporte de P2.

## 1.4 · Catálogos en CSV (P2)

**Estado:** completado.

Se generaron los catálogos de `db/seed/catalogos/` copiando los valores del
Anexo B y los códigos postales de `codigos-postales-mendoza.md`. Los archivos
están en UTF-8 sin BOM, con separador coma y cabeceras en `snake_case`.

| Archivo | Cabecera | Filas | Destino |
|---|---|---:|---|
| `cepas.csv` | `nombre,tipo` | 12 | `cepa` |
| `maridajes.csv` | `nombre,temperatura_servicio` | 8 | `maridaje` |
| `localidades_mendoza.csv` | `codigo_postal,nombre,provincia` | 18 | `localidad` |
| `tipos_vino.csv` | `tipo` | 4 | Lista de referencia para `vino.tipo` |
| `presentaciones.csv` | `presentacion_ml` | 5 | Lista de referencia para `vino.presentacion_ml` |

- **Cepas:** 7 tintas y 5 blancas. Se respetaron los nombres exactos del Anexo
  B.1; no se agregaron Cabernet Franc ni Viognier.
- **Maridajes:** 8 filas con la temperatura única del Anexo B.2.
- **Localidades:** 18 departamentos de Mendoza, con código postal de 4 dígitos
  único y `provincia = 'Mendoza'`. El CSV no incluye `id_localidad` ni
  `encargado_regional`.
- **Tipos y presentaciones:** listas de referencia para validar los `CHECK` de
  `002_constraints.sql`; no se cargan en tablas propias.
- **Sin IDs:** las claves subrogadas las genera PostgreSQL. `codigo_postal` se
  usa como clave natural de `localidad` en el CSV; el esquema físico conserva
  `id_localidad` como PK (decisión de equipo, issue #6 cerrada). Para
  `vino.cod_vino` se usa `GENERATED ALWAYS AS IDENTITY` según Anexo A.2.
- **Encargado regional:** se completará en `seed.py` con Faker `es_AR` y semilla
  fija, después de cargar las localidades. No se inventa en el CSV.

El orden de carga es fijo: `cepas` → `maridajes` → `localidades`. Al no incluir
IDs y reiniciar las identidades entre corridas, dos ejecuciones con la misma
semilla producen los mismos datos.

**Cómo verificar:** con `001_esquema.sql` y `002_constraints.sql` aplicados en
una base temporal, cargar los tres catálogos con `\copy` y comprobar:

```sql
SELECT 'cepa' AS tabla, count(*) AS filas, count(DISTINCT nombre) AS unicos FROM cepa
UNION ALL SELECT 'maridaje', count(*), count(DISTINCT nombre) FROM maridaje
UNION ALL SELECT 'localidad', count(*), count(DISTINCT codigo_postal) FROM localidad;
```

Resultado esperado: `cepa` 12/12, `maridaje` 8/8 y `localidad` 18/18. También se
verificó que 7 cepas son tintas, 5 blancas, que las 18 localidades son de
Mendoza y que una recarga con `TRUNCATE ... RESTART IDENTITY CASCADE` conserva
los mismos IDs y el mismo contenido.

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
