# Tablero (7.6)

Página `#/tablero` con los tres reportes de la consigna: top 10 de vinos más
vendidos, ventas por sala del último trimestre (gráfico de barras) y vinos sin
stock en una sala elegida. Todos los números provienen de la API; el cliente
sólo los formatea y, en el gráfico, escala el ancho de las barras.

## Qué se agregó

| Archivo | Cambio |
|---|---|
| `front/src/pages/tablero.js` | Página `#/tablero` con las tres tarjetas y sus estados de carga/error. |
| `front/src/api/reportes.js` | `topVinos`, `ventasPorSala`, `vinosSinStock`. |
| `front/src/main.js` | Ruta `#/tablero`. |
| `front/index.html`, `front/src/pages/catalogo.js` | Accesos «Tablero». |
| `front/src/styles/main.css` | Gráfico de barras, tarjeta ancha y ajuste responsive. |

## Endpoints usados

| Sección | Endpoint | Campos que se muestran |
|---|---|---|
| Top 10 | `GET /reportes/top-vinos?limite=10` | `cod_vino`, `nombre_comercial`, `botellas_vendidas` |
| Ventas | `GET /reportes/ventas-por-sala?desde=…&hasta=…` | `id_sala`, `localidad`, `mes`, `botellas_vendidas`, `monto_total` |
| Sin stock | `GET /reportes/vinos-sin-stock?id_sala=…` | `cod_vino`, `nombre_comercial`, `stock_sala`, `stock_deposito` |

Cada tarjeta carga en paralelo e informa su propio error con el mensaje
verbatim de la API (`htmlError`), sin reemplazarlo.

## Último trimestre

La página calcula el rango de presentación: desde el día 1 del mes de hace dos
meses hasta hoy, y **siempre envía `desde` y `hasta`**. Se detectó que la API,
si se omiten ambos parámetros, devuelve todo el historial (`vw_ventas_mensuales_sala`
sin filtro; se observaron filas de 2021) aunque el contrato diga «por defecto,
último trimestre». El front no depende de ese default; queda como observación
para P3 en #30.

El ancho de cada barra se escala contra el mayor `monto_total` del período sólo
para dibujar; el monto que se muestra es el devuelto por la API y no se suma ni
recalcula en el cliente. La etiqueta `mes` se muestra como `sep 2026`, un
formato de presentación.

## Sala

No existe `GET /salas` en el contrato, así que la tarjeta de vinos sin stock
pide el ID de sala (por defecto 1) y lo aclara con un texto de ayuda. La API no
valida que la sala exista: para un ID inexistente devuelve todos los vinos con
stock en depósito (no hay filas de `stock_sala`), comportamiento que la página
muestra tal cual.

## Verificación

### Build

```text
vite v8.3.6 building client environment for production...
✓ 20 modules transformed.
dist/index.html                  1.11 kB │ gzip:  0.52 kB
dist/assets/index-Bp7hNVam.css   9.63 kB │ gzip:  2.39 kB
dist/assets/index-CR_F34e9.js   44.40 kB │ gzip: 10.57 kB
✓ built in 148ms
```

### Prueba DOM contra la API real

Con `uvicorn` (rama de #30) y PostgreSQL 16.15 con `seed --scale small`. El
test crea dos ventas del día (salas 1 y 2, vinos 17 y 21) para que el gráfico
tenga filas dentro del trimestre:

```text
e2e 7.6 OK: ranking, gráfico y vinos sin stock con datos de la API
ventas creadas: 51 52
```

Verificaciones incluidas:

- El ranking trae exactamente 10 filas y el encabezado «Botellas vendidas».
- El gráfico muestra las salas 1 y 2 del mes actual, montos con `$` y al menos
  una barra al 100 % (escala sobre el máximo de la API).
- La sala 1 lista «Ellas Reserva» y no lista el vino 17, que sí tiene stock en
  esa sala.
- Al consultar la sala 2, la tabla se actualiza: aparece el vino 17 y desaparece
  el 21, que tiene stock en la sala 2.
- Los tres estados de carga se ocultan al terminar y los errores se muestran
  dentro de la tarjeta correspondiente.

## Notas

- **Sin GET /salas**: se ingresa el ID (pedido a P3 junto con `GET /cepas` y
  `GET /bodegas`).
- **Sin lógica de negocio en el cliente**: no se calculan importes, stock ni
  agregados; sólo se formatean los valores de la API y se escala el dibujo.
- **Dependencia**: rama apilada sobre `feat/7.5-front-transferencias` → `7.4` →
  `7.3` → `7.1`. Retargetear a `main` cuando se mergeen las anteriores.
