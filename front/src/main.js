import './styles/main.css';
import { onRouteChange, readRoute } from './router.js';
import { renderCatalogo } from './pages/catalogo.js';
import { renderVinoDetalle } from './pages/vino-detalle.js';
import { renderVinoForm } from './pages/vino-form.js';
import { renderVentaNueva } from './pages/venta-nueva.js';
import { renderTransferenciaNueva } from './pages/transferencia-nueva.js';
import { renderTablero } from './pages/tablero.js';

const outlet = document.querySelector('#app');
let cleanup = () => {};

function render() {
  cleanup();
  cleanup = () => {};

  const { pathname, query } = readRoute();
  const editar = pathname.match(/^\/vinos\/([^/]+)\/editar\/?$/);
  const detalle = pathname.match(/^\/vinos\/([^/]+)\/?$/);

  if (pathname === '/vinos/nuevo') {
    cleanup = renderVinoForm(outlet) || cleanup;
    return;
  }

  if (pathname === '/ventas/nueva') {
    cleanup = renderVentaNueva(outlet) || cleanup;
    return;
  }

  if (pathname === '/transferencias/nueva') {
    cleanup = renderTransferenciaNueva(outlet) || cleanup;
    return;
  }

  if (pathname === '/tablero') {
    cleanup = renderTablero(outlet) || cleanup;
    return;
  }

  if (editar) {
    cleanup = renderVinoForm(outlet, { codVino: decodeURIComponent(editar[1]) }) || cleanup;
    return;
  }

  if (detalle) {
    cleanup = renderVinoDetalle(outlet, decodeURIComponent(detalle[1])) || cleanup;
    return;
  }

  cleanup = renderCatalogo(outlet, query) || cleanup;
}

onRouteChange(render);
