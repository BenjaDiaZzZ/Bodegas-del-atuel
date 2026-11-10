# Alta y edición de vino (7.3)

Formulario de alta y edición contra la API real, con composición de cepas
dinámica. La suma de porcentajes **no se bloquea en el cliente**: se envía y el
error que se muestra es el que devuelve la base a través de la API.

## Qué se agregó

| Archivo | Cambio |
|---|---|
| `front/src/pages/vino-form.js` | Página de alta (`#/vinos/nuevo`) y edición (`#/vinos/:cod/editar`). Filas de composición dinámicas, precarga en edición y banner de error con el mensaje de la API. |
| `front/src/api/client.js` | `api.post` y `api.put` con cuerpo JSON; `204` devuelve `null`. |
| `front/src/api/vinos.js` | `crearVino` y `actualizarVino`. |
| `front/src/main.js` | Rutas `#/vinos/nuevo` y `#/vinos/:cod/editar` antes del detalle. |
| `front/src/pages/catalogo.js` | Botón «Nuevo vino». |
| `front/src/pages/vino-detalle.js` | Botón «Editar vino». |
| `front/index.html` | Acceso «Nuevo vino» en la barra superior. |
| `front/src/styles/main.css` | Estilos del formulario, composición y banner de error. |

El formulario no calcula importes ni stock: sólo arma el cuerpo del contrato
(`VinoCreate` / `VinoUpdate`). La suma parcial se muestra como ayuda visual, pero
la validación que decide es la de la base.

## Verificación

### Build

```text
vite v8.3.6 building client environment for production...
✓ 12 modules transformed.
dist/index.html                  0.95 kB │ gzip: 0.49 kB
dist/assets/index-BD8ZnSyx.css   7.10 kB │ gzip: 1.97 kB
dist/assets/index-BXxbiO4y.js   19.50 kB │ gzip: 5.96 kB
✓ built in 120ms
```

### Prueba DOM contra la API real

Se ejecutó la página en jsdom contra `uvicorn` (rama de #30) y PostgreSQL 16.15
con `seed --scale small`:

```text
BANNER_RN05 :: [RN-05] La composicion del vino 102 suma 90.00, debe sumar 100
                HTTP 409 · código P0001 · regla RN-05
PASS formulario de alta renderizado
PASS agrega una fila de composición
PASS muestra la suma parcial sin bloquear
PASS el error visible es el mensaje de la API
PASS el error incluye la regla RN-05
PASS el error incluye el estado HTTP 409
PASS suma parcial corregida
PASS el alta navega al detalle creado
PASS la edición precarga el nombre
PASS la edición precarga la composición
PASS la edición precarga los porcentajes
PASS la edición persiste el nombre
PASS limpieza del vino de prueba
OK 13 verificaciones
```

La prueba de RN-05 envía una composición 60/30: el banner muestra el `mensaje`
de la API **sin reemplazarlo** y agrega `HTTP 409 · código P0001 · regla RN-05`.
Corregida a 60/40, el alta responde 201 y navega al detalle.

## Notas

- **Catálogos**: `GET /cepas` y `GET /bodegas` no están en el contrato. El
  formulario usa IDs numéricos (cepa) y CUIT (bodega); cuando P3 agregue
  `GET /cepas` (pedido en el PR #30) se puede pasar a un selector sin tocar la
  capa de llamadas.
- **Borrado**: editar el precio genera una fila en `auditoria_precio` (RN-13) y
  el FK de esa tabla impide después borrar el vino (`23503`, RN-14). Es el
  comportamiento esperado del backend; la prueba edita el nombre para poder
  limpiar el registro.
- **Dependencia**: la rama está apilada sobre `feat/7.1-7.2-front-catalogo`
  (PR #18). Cuando se mergee, se retargetea a `main`.
