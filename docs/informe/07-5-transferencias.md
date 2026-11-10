# Transferencias (7.5)

Alta de una transferencia depósito → sala, carga de renglones y avance de
estado con botones habilitados según el estado actual. Los renglones sólo se
editan en `en_confeccion`; el stock se mueve al procesar y lo hace el
procedimiento de la base.

## Qué se agregó

| Archivo | Cambio |
|---|---|
| `front/src/pages/transferencia-nueva.js` | Página `#/transferencias/nueva`: creación, búsqueda de vinos, renglones, estado y acciones. |
| `front/src/api/transferencias.js` | `crearTransferencia`, `agregarRenglonTransferencia`, `terminarTransferencia`, `procesarTransferencia`. |
| `front/src/main.js` | Ruta `#/transferencias/nueva`. |
| `front/index.html`, `front/src/pages/catalogo.js` | Accesos «Transferencias». |

Estados y botones:

| Estado | Cargar renglones | Terminar | Procesar |
|---|---|---|---|
| `en_confeccion` | sí | habilitado | deshabilitado |
| `terminado` | no (la API responde RN-12) | deshabilitado | habilitado |
| `procesado` | no | deshabilitado | deshabilitado |

Cada respuesta de la API (`POST` de creación, renglón, terminar y procesar)
devuelve la transferencia completa; la página re-renderiza con ese estado. Si
una acción falla, el estado no avanza y el botón queda disponible para
reintentar.

## Verificación

### Build

```text
vite v8.3.6 building client environment for production...
✓ 18 modules transformed.
dist/index.html                  1.07 kB │ gzip: 0.51 kB
dist/assets/index-BCRtGQib.css   8.93 kB │ gzip: 2.27 kB
dist/assets/index-DzmBlnvM.js   37.47 kB │ gzip: 9.16 kB
✓ built in 112ms
```

### Prueba DOM contra la API real

Con `uvicorn` (rama de #30) y PostgreSQL 16.15 con `seed --scale small`:

```text
BANNER_PROCESAR :: [RN-11] Stock insuficiente en el deposito del vino 7:
                   hay 483, se piden 999999
                   HTTP 409 · código P0001 · regla RN-11
PASS creada en confección
PASS terminar habilitado en confección
PASS procesar deshabilitado en confección
PASS permite cargar renglones en confección
PASS el vino queda seleccionado
PASS renglón cargado
PASS sigue en confección
PASS terminar deshabilitado tras terminar
PASS procesar habilitado tras terminar
PASS ya no permite editar renglones
PASS terminar deshabilitado tras procesar
PASS procesar deshabilitado tras procesar
PASS muestra confirmación de stock movido
PASS el error visible es el mensaje de la API
PASS el error incluye la regla RN-11
PASS el estado no avanza si falla
PASS procesar sigue habilitado para reintentar
OK 18 verificaciones
```

Se probaron dos transferencias: la primera con stock suficiente termina en
`procesado` y mueve el stock; la segunda con `cantidad: 999999` falla al
procesar con `[RN-11]`, muestra ese mensaje sin reemplazarlo y permanece en
`terminado`.

## Notas

- **Sin GET de transferencias**: el contrato sólo tiene creación, renglón,
  terminar y procesar. El estado vive en memoria mientras la página está
  abierta; al recargar se pierde. Queda pendiente un `GET /transferencias/{nro}`
  (y un listado) para retomar una transferencia existente.
- **Sala**: se ingresa el ID porque no hay `GET /salas` (pedido a P3 junto con
  `GET /cepas`).
- **Stock**: el cliente no calcula ni consulta stock; muestra el error de la
  base al procesar.
- **Dependencia**: rama apilada sobre `feat/7.4-front-venta` → `7.3` → `7.1`.
  Retargetear a `main` cuando se mergeen las anteriores.
