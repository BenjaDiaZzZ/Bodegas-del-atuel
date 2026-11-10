# Nueva venta (7.4)

Alta de una venta completa desde el front: elegir cliente, sala y vinos, y
mostrar los totales que devuelve el backend. El cliente **no calcula importes
ni stock**: envía sólo `id_cliente`, `id_sala` y `(cod_vino, cantidad)`; la base
calcula precios, descuentos, subtotales y total, y rechaza la venta si no hay
stock.

## Qué se agregó

| Archivo | Cambio |
|---|---|
| `front/src/pages/venta-nueva.js` | Página `#/ventas/nueva`: búsqueda de cliente, sala, fecha opcional, búsqueda de vinos, renglones con cantidad, banner de error y resumen con totales de la API. |
| `front/src/api/clientes.js` | `listarClientes` paginado con búsqueda `q`. |
| `front/src/api/ventas.js` | `crearComprobante` (`POST /comprobantes`). |
| `front/src/utils/errors.js` | Render del error de API compartido con 7.3 (mensaje, HTTP, código, regla y detalle). |
| `front/src/main.js` | Ruta `#/ventas/nueva`. |
| `front/src/pages/vino-form.js` | Usa el render de errores compartido. |
| `front/index.html`, `front/src/pages/catalogo.js` | Accesos «Nueva venta». |
| `front/src/styles/main.css` | Búsquedas, renglones, cliente elegido y totales. |

Flujo:

1. Se buscan clientes por nombre/documento (`GET /clientes?q=`) y se elige uno.
2. Se ingresa la sala y, opcionalmente, la fecha.
3. Se buscan vinos por nombre (`GET /vinos?nombre=`) y se agregan renglones con
   cantidad. El precio unitario se muestra sólo como dato de la API.
4. `POST /comprobantes` devuelve el comprobante con `subtotal`, `descuento`,
   `total` y los renglones calculados por la base; la página muestra ese
   resumen.

## Verificación

### Build

```text
vite v8.3.6 building client environment for production...
✓ 16 modules transformed.
dist/index.html                  1.00 kB │ gzip: 0.50 kB
dist/assets/index-BCRtGQib.css   8.93 kB │ gzip: 2.27 kB
dist/assets/index-DyQ31LRG.js   29.75 kB │ gzip: 7.89 kB
✓ built in 321ms
```

### Prueba DOM contra la API real

Con `uvicorn` (rama de #30) y PostgreSQL 16.15 con `seed --scale small`:

```text
BANNER_STOCK :: [RN-09] Stock insuficiente del vino 73 en la sala 1:
                 disponible 58, solicitado 99999
                 HTTP 409 · código P0001 · regla RN-09
PASS cliente seleccionado
PASS renglón agregado desde la búsqueda
PASS el error visible es el mensaje de la API
PASS el error incluye la regla RN-09
PASS el error incluye HTTP 409
PASS el backend devolvió el comprobante
PASS muestra el número de comprobante
PASS muestra el total devuelto por el backend
PASS muestra los renglones con precio de la base
OK 9 verificaciones
```

La primera venta se envía con `cantidad: 99999`: la API responde 409 con
`[RN-09]` y el banner muestra ese mensaje **sin reemplazarlo**. Corregida a
`cantidad: 2`, la API responde 201 y la página muestra el `total` devuelto (no
calculado en el cliente). La transacción de la API deja la base intacta cuando
falla por stock.

## Notas

- **Sala**: el contrato no expone `GET /salas`, así que se ingresa el ID (igual
  que `GET /cepas` en 7.3). Queda como pendiente para P3 (junto con `GET /cepas` de 7.3);
  cuando exista, se cambia a un selector sin tocar la capa de llamadas.
- **Duplicados**: agregar dos veces el mismo vino se evita en la UI (la PK
  compuesta de renglón lo rechazaría con 409).
- **Alcance**: esta tarea no incluye listado ni detalle de comprobantes; la
  página de éxito muestra el resumen devuelto por la API.
- **Dependencia**: rama apilada sobre `feat/7.3-front-crud` (#32), que a su vez
  depende de `feat/7.1-7.2-front-catalogo` (#18). Al mergearse, retargetear a
  `main`.
