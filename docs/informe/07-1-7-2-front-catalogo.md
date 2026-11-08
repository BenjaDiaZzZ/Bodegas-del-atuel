# 7.1 y 7.2 · Estructura del front y catálogo de vinos

**Responsable:** P4 (Front e Infraestructura)
**Dependencias:** 1.7 (`api/openapi.yaml`) y 1.8 (mock con Prism y CI), ambas mergeadas en `main`.

## Objetivo

- **7.1:** crear `front/` con una única capa de llamadas a la API y la URL base configurable.
- **7.2:** implementar el catálogo de vinos con paginación, filtros por nombre, tipo, cepa, bodega y añada, y detalle con composición, maridajes y stock.

El front consume únicamente la API y no calcula totales, descuentos ni stock.

## Estructura

```text
front/
├── index.html
├── package.json
├── package-lock.json
├── vite.config.js
├── .env.example
└── src/
    ├── main.js
    ├── router.js
    ├── api/
    │   ├── client.js
    │   └── vinos.js
    ├── pages/
    │   ├── catalogo.js
    │   └── vino-detalle.js
    ├── styles/
    │   └── main.css
    └── utils/
        └── format.js
```

Se usa **vanilla JavaScript + Vite**. No hay framework ni lógica de negocio en el cliente.

## 7.1 · Capa de llamadas y URL configurable

`src/api/client.js` es la única capa que usa `fetch`. Expone `api.get()`, normaliza la respuesta y convierte los errores de la API en `ApiError` conservando `codigo`, `mensaje`, `detalle` y `regla`.

La URL base se resuelve así:

- En desarrollo: `/api`, que Vite redirige al mock de Prism (`http://127.0.0.1:4010`) mediante `server.proxy` en `vite.config.js`. Así se evita CORS.
- En build: `import.meta.env.VITE_API_URL`, definida al compilar.

Ejemplo de build para la nube:

```bash
cd front
VITE_API_URL=https://api.bodegas-del-atuel.example npm run build
```

Cambiar de entorno no requiere tocar código, que es la condición de "hecho" de 7.1.

`front/.env.example` documenta `VITE_API_URL` y la variable opcional `VITE_MOCK_URL` para el proxy local.

## 7.2 · Catálogo y detalle

Endpoints consumidos:

- `GET /vinos` con `page`, `per_page`, `nombre`, `tipo`, `id_cepa`, `cuit_bodega` y `anada`.
- `GET /vinos/{cod}` para el detalle.

Decisiones de implementación:

- **Paginación del servidor:** se muestran los controles a partir de `meta.page` y `meta.total_pages`; el front no pagina en memoria.
- **Filtros en la URL:** los filtros y la página viven en el hash (`#/?tipo=tinto&anada=2021&page=2`). Recargar o compartir el enlace conserva el estado.
- **Navegación por hash:** un router mínimo permite alternar entre catálogo y detalle (`#/` y `#/vinos/{cod}`) sin recargar la página.
- **Cepa y bodega:** el contrato no expone endpoints de catálogos (`/cepas`, `/bodegas`), por lo que no se pueden poblar selects desde la API. Los filtros aceptan el ID de cepa y el CUIT de bodega, y desde el detalle se puede navegar al catálogo ya filtrado haciendo clic en la bodega, el tipo, la añada o una cepa de la composición.
- **Mensajes de error:** se muestra el `mensaje` devuelto por la API, sin reemplazarlo por un texto genérico.
- **Sin lógica de negocio:** precios, stock y composición se muestran tal como llegan. El único formateo es de presentación (`Intl.NumberFormat`).

## Cómo ejecutarlo

Terminal 1, mock de la API:

```bash
./scripts/mock_api.sh
```

Terminal 2, front:

```bash
cd front
npm install
npm run dev
```

Queda disponible en `http://127.0.0.1:5173`.

## Verificación

### Build

```text
vite v8.3.6 building client environment for production...
✓ 11 modules transformed.
dist/index.html                  0.92 kB
dist/assets/index-B7moAJdV.css   5.88 kB
dist/assets/index-DbSeMVGg.js   11.21 kB
✓ built in 131ms
```

### Proxy contra el mock

Con Prism en `4010` y Vite en `5173`:

```text
GET http://127.0.0.1:5173/api/vinos?page=1&per_page=2
data: 1 · meta: {page: 1, per_page: 20, total: 137, total_pages: 7}
primer vino: Malbec Reserva · tinto · 2021

GET http://127.0.0.1:5173/api/vinos/1
cod: 1 · nombre: Malbec Reserva
composicion: 1 · maridajes: 1
stock: {deposito: 120, salas: 45, total: 165}
```

### Pruebas de renderizado

Se ejecutó el bundle compilado en un DOM de prueba (jsdom) con respuestas simuladas del contrato:

```text
PASS catálogo: fila renderizada con datos de la API
PASS detalle: composición, maridajes y stock renderizados
PASS filtros: query string aplicada a la llamada y al formulario
PASS error: mensaje de la API mostrado sin reemplazarlo
```

## Alcance y pendientes

- El catálogo quedó verificado contra el **mock**. La condición "funciona contra la API real" se completa cuando P3 entregue los endpoints de la Fase 6.
- La integración del front en `docker-compose.yml` corresponde a 7.7.
- Si se agregan endpoints de catálogos (`GET /cepas`, `GET /bodegas`) al contrato, los filtros de cepa y bodega pueden pasar de inputs a selects sin cambiar la capa de llamadas.
- Los estilos son propios y mínimos; el foco de la Fase 7 es el flujo del dato, no el diseño visual.
