import { listarVinos } from '../api/vinos.js';
import { navigate } from '../router.js';
import { escapeHtml, numero, precio, presentacion, tipoVino } from '../utils/format.js';

const TIPOS = ['tinto', 'blanco', 'rosado', 'espumante'];
const PER_PAGE = 12;

export function renderCatalogo(outlet, query) {
  const controller = new AbortController();
  const filtros = leerFiltros(query);
  outlet.innerHTML = plantilla(filtros);

  const form = outlet.querySelector('#filtros');
  const estado = outlet.querySelector('#estado');
  const resultado = outlet.querySelector('#resultado');
  const paginacion = outlet.querySelector('#paginacion');

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    navigate('/', paramsDesdeFormulario(new FormData(form), 1));
  });

  outlet.querySelector('#limpiar').addEventListener('click', () => navigate('/'));

  paginacion.addEventListener('click', (event) => {
    const boton = event.target.closest('button[data-page]');
    if (!boton || boton.disabled) return;
    navigate('/', paramsDesdeFiltros(filtros, Number(boton.dataset.page)));
  });

  cargar();

  async function cargar() {
    estado.className = 'status';
    estado.textContent = 'Cargando vinos…';
    resultado.innerHTML = '';
    paginacion.innerHTML = '';

    try {
      const pagina = await listarVinos({ ...filtros, perPage: PER_PAGE }, { signal: controller.signal });
      mostrarPagina(pagina);
    } catch (error) {
      if (error.name === 'AbortError') return;
      estado.className = 'status status-error';
      estado.textContent = error.message;
    }
  }

  function mostrarPagina(pagina) {
    const vinos = Array.isArray(pagina?.data) ? pagina.data : [];
    const meta = pagina?.meta ?? { page: 1, per_page: PER_PAGE, total: 0, total_pages: 1 };

    if (vinos.length === 0) {
      estado.className = 'status';
      estado.textContent = 'No se encontraron vinos con esos filtros.';
      return;
    }

    estado.className = 'status status-ok';
    estado.textContent = `${numero(meta.total)} vino${meta.total === 1 ? '' : 's'} · página ${meta.page} de ${meta.total_pages}`;
    resultado.innerHTML = tabla(vinos);
    paginacion.innerHTML = paginador(meta);
  }

  return () => controller.abort();
}

function leerFiltros(query) {
  const page = Number.parseInt(query.get('page') ?? '1', 10);
  const tipo = query.get('tipo') ?? '';

  return {
    page: Number.isFinite(page) && page > 0 ? page : 1,
    nombre: (query.get('nombre') ?? '').trim(),
    tipo: TIPOS.includes(tipo) ? tipo : '',
    idCepa: (query.get('id_cepa') ?? '').trim(),
    cuitBodega: (query.get('cuit_bodega') ?? '').trim(),
    anada: (query.get('anada') ?? '').trim(),
  };
}

function paramsDesdeFormulario(formData, page) {
  const params = new URLSearchParams();

  for (const campo of ['nombre', 'tipo', 'id_cepa', 'cuit_bodega', 'anada']) {
    const valor = String(formData.get(campo) ?? '').trim();
    if (valor) params.set(campo, valor);
  }

  if (page > 1) params.set('page', String(page));
  return params;
}

function paramsDesdeFiltros(filtros, page) {
  const params = new URLSearchParams();

  if (filtros.nombre) params.set('nombre', filtros.nombre);
  if (filtros.tipo) params.set('tipo', filtros.tipo);
  if (filtros.idCepa) params.set('id_cepa', filtros.idCepa);
  if (filtros.cuitBodega) params.set('cuit_bodega', filtros.cuitBodega);
  if (filtros.anada) params.set('anada', filtros.anada);
  if (page > 1) params.set('page', String(page));

  return params;
}

function plantilla(filtros) {
  return `
    <section class="page">
      <div class="page-header">
        <div>
          <h1>Catálogo de vinos</h1>
          <p class="muted">Listado paginado y filtrado desde la API.</p>
        </div>
        <span class="pill">Datos de la API</span>
      </div>

      <div class="page-actions">
        <a class="button" href="#/vinos/nuevo">Nuevo vino</a>
      </div>

      <form id="filtros" class="filters" role="search">
        <label class="field">
          <span>Nombre</span>
          <input name="nombre" type="search" value="${escapeHtml(filtros.nombre)}" placeholder="Ej.: Malbec" autocomplete="off" />
        </label>
        <label class="field">
          <span>Tipo</span>
          <select name="tipo">
            <option value="">Todos</option>
            ${TIPOS.map((tipo) => `<option value="${tipo}"${filtros.tipo === tipo ? ' selected' : ''}>${tipoVino(tipo)}</option>`).join('')}
          </select>
        </label>
        <label class="field">
          <span>Cepa (ID)</span>
          <input name="id_cepa" type="number" min="1" step="1" value="${escapeHtml(filtros.idCepa)}" placeholder="Ej.: 1" />
        </label>
        <label class="field">
          <span>Bodega (CUIT)</span>
          <input name="cuit_bodega" type="text" inputmode="numeric" maxlength="11" pattern="[0-9]{11}" value="${escapeHtml(filtros.cuitBodega)}" placeholder="11 dígitos" />
        </label>
        <label class="field">
          <span>Añada</span>
          <input name="anada" type="number" min="1900" max="2100" step="1" value="${escapeHtml(filtros.anada)}" placeholder="Ej.: 2021" />
        </label>
        <div class="filter-actions">
          <button class="button" type="submit">Buscar</button>
          <button class="button button-secondary" type="button" id="limpiar">Limpiar</button>
        </div>
      </form>

      <p id="estado" class="status" role="status"></p>
      <div id="resultado"></div>
      <nav id="paginacion" class="pagination" aria-label="Paginación"></nav>
    </section>
  `;
}

function tabla(vinos) {
  return `
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th scope="col">Vino</th>
            <th scope="col">Tipo</th>
            <th scope="col">Añada</th>
            <th scope="col">Presentación</th>
            <th scope="col">Bodega</th>
            <th scope="col" class="num">Precio</th>
            <th scope="col" class="num">Graduación</th>
            <th scope="col"><span class="sr-only">Detalle</span></th>
          </tr>
        </thead>
        <tbody>
          ${vinos.map(fila).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function fila(vino) {
  const cod = encodeURIComponent(vino.cod_vino);
  const tipo = encodeURIComponent(vino.tipo);
  const anada = encodeURIComponent(vino.anada);
  const cuit = encodeURIComponent(vino.cuit_bodega);

  return `
    <tr>
      <td><a class="link" href="#/vinos/${cod}">${escapeHtml(vino.nombre_comercial)}</a></td>
      <td><a class="link-muted" href="#/?tipo=${tipo}">${escapeHtml(tipoVino(vino.tipo))}</a></td>
      <td><a class="link-muted" href="#/?anada=${anada}">${escapeHtml(vino.anada)}</a></td>
      <td>${escapeHtml(presentacion(vino.presentacion_ml))}</td>
      <td><a class="link-muted" href="#/?cuit_bodega=${cuit}">${escapeHtml(vino.bodega || vino.cuit_bodega)}</a></td>
      <td class="num">${escapeHtml(precio(vino.precio_venta))}</td>
      <td class="num">${escapeHtml(numero(vino.graduacion))} %</td>
      <td class="num"><a class="button button-small" href="#/vinos/${cod}">Ver</a></td>
    </tr>
  `;
}

function paginador(meta) {
  const total = Number(meta.total_pages) || 1;
  const actual = Math.min(Math.max(Number(meta.page) || 1, 1), total);

  if (total <= 1) return '';

  const desde = Math.max(1, actual - 2);
  const hasta = Math.min(total, actual + 2);
  const botones = [botonPagina('‹', actual - 1, actual === 1, 'Página anterior')];

  for (let pagina = desde; pagina <= hasta; pagina += 1) {
    botones.push(botonPagina(String(pagina), pagina, false, `Página ${pagina}`, pagina === actual));
  }

  botones.push(botonPagina('›', actual + 1, actual === total, 'Página siguiente'));
  return botones.join('');
}

function botonPagina(texto, pagina, deshabilitado, etiqueta, activo = false) {
  const clases = ['button', 'button-small', 'button-page'];
  if (activo) clases.push('is-active');

  return `<button type="button" class="${clases.join(' ')}" data-page="${pagina}" ${deshabilitado ? 'disabled' : ''} aria-label="${escapeHtml(etiqueta)}"${activo ? ' aria-current="page"' : ''}>${texto}</button>`;
}
