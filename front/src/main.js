import './styles/main.css';
import { onRouteChange, readRoute } from './router.js';
import { renderCatalogo } from './pages/catalogo.js';
import { renderVinoDetalle } from './pages/vino-detalle.js';

const outlet = document.querySelector('#app');
let cleanup = () => {};

function render() {
  cleanup();
  cleanup = () => {};

  const { pathname, query } = readRoute();
  const detalle = pathname.match(/^\/vinos\/([^/]+)\/?$/);

  if (detalle) {
    cleanup = renderVinoDetalle(outlet, decodeURIComponent(detalle[1])) || cleanup;
    return;
  }

  cleanup = renderCatalogo(outlet, query) || cleanup;
}

onRouteChange(render);
