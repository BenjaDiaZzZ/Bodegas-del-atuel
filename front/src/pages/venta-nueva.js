import { listarClientes } from '../api/clientes.js';
import { listarVinos } from '../api/vinos.js';
import { crearComprobante } from '../api/ventas.js';
import { htmlError } from '../utils/errors.js';
import { escapeHtml, numero, precio, tipoVino } from '../utils/format.js';

const CLIENTES_PER_PAGE = 6;
const VINOS_PER_PAGE = 6;

export function renderVentaNueva(outlet) {
  const controller = new AbortController();
  let cliente = null;

  outlet.innerHTML = plantilla();

  const form = outlet.querySelector('#venta-form');
  const banner = outlet.querySelector('#venta-error');
  const resultadosClientes = outlet.querySelector('#clientes-resultados');
  const clienteElegido = outlet.querySelector('#cliente-elegido');
  const resultadosVinos = outlet.querySelector('#vinos-resultados');
  const renglones = outlet.querySelector('#renglones');
  const boton = form.querySelector('button[type="submit"]');
  const qCliente = outlet.querySelector('#cliente-q');
  const qVino = outlet.querySelector('#vino-q');

  outlet.querySelector('#buscar-clientes').addEventListener('click', () => buscarClientes());
  outlet.querySelector('#buscar-vinos').addEventListener('click', () => buscarVinos());

  qCliente.addEventListener('keydown', (event) => {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    buscarClientes();
  });

  qVino.addEventListener('keydown', (event) => {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    buscarVinos();
  });

  resultadosClientes.addEventListener('click', (event) => {
    const elegido = event.target.closest('button[data-cliente]');
    if (!elegido) return;

    cliente = {
      id_cliente: Number(elegido.dataset.cliente),
      nombre: elegido.dataset.nombre,
      tipo: elegido.dataset.tipo,
      descuento: Number(elegido.dataset.descuento),
    };
    clienteElegido.classList.add('selected-item-ok');
    clienteElegido.innerHTML = `Cliente: <strong>${escapeHtml(cliente.nombre)}</strong> · ${escapeHtml(tipoVino(cliente.tipo))} · descuento ${escapeHtml(numero(cliente.descuento))} % (lo aplica la base)`;
  });

  resultadosVinos.addEventListener('click', (event) => {
    const elegido = event.target.closest('button[data-vino]');
    if (!elegido) return;

    agregarRenglon({
      cod_vino: Number(elegido.dataset.vino),
      nombre: elegido.dataset.nombre,
      precio: Number(elegido.dataset.precio),
    });
  });

  renglones.addEventListener('click', (event) => {
    const quitar = event.target.closest('button[data-remove]');
    if (!quitar) return;
    quitar.closest('.renglon-row').remove();
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    ocultarError();

    if (!cliente) {
      mostrarMensaje('Elegí un cliente antes de registrar la venta.');
      return;
    }

    const datos = leerVenta(form, renglones, cliente);
    const textoOriginal = boton.textContent;
    boton.disabled = true;
    boton.textContent = 'Registrando…';

    try {
      const comprobante = await crearComprobante(datos, { signal: controller.signal });
      outlet.innerHTML = plantillaExito(comprobante);
    } catch (error) {
      if (error.name === 'AbortError') return;
      mostrarError(error);
      boton.disabled = false;
      boton.textContent = textoOriginal;
    }
  });

  cargarClientes();

  return () => controller.abort();

  async function cargarClientes(q = '') {
    resultadosClientes.innerHTML = '<p class="muted">Cargando clientes…</p>';
    try {
      const pagina = await listarClientes({ q, perPage: CLIENTES_PER_PAGE }, { signal: controller.signal });
      pintarClientes(pagina);
    } catch (error) {
      if (error.name === 'AbortError') return;
      resultadosClientes.innerHTML = '';
      mostrarError(error);
    }
  }

  async function buscarClientes() {
    await cargarClientes(qCliente.value.trim());
  }

  function pintarClientes(pagina) {
    const clientes = Array.isArray(pagina?.data) ? pagina.data : [];
    if (clientes.length === 0) {
      resultadosClientes.innerHTML = '<p class="muted">Sin clientes para esa búsqueda.</p>';
      return;
    }

    resultadosClientes.innerHTML = clientes
      .map(
        (item) => `
          <button type="button" class="search-result" data-cliente="${item.id_cliente}" data-nombre="${escapeHtml(item.nombre)}" data-tipo="${escapeHtml(item.tipo)}" data-descuento="${item.descuento}">
            <span class="search-result-title">${escapeHtml(item.nombre)}</span>
            <span class="search-result-meta">#${item.id_cliente} · ${escapeHtml(tipoVino(item.tipo))} · ${escapeHtml(item.tipo_documento)} ${escapeHtml(item.nro_documento)}</span>
          </button>
        `,
      )
      .join('');
  }

  async function buscarVinos() {
    const q = qVino.value.trim();
    resultadosVinos.innerHTML = '<p class="muted">Buscando vinos…</p>';
    try {
      const pagina = await listarVinos({ nombre: q, perPage: VINOS_PER_PAGE }, { signal: controller.signal });
      pintarVinos(pagina);
    } catch (error) {
      if (error.name === 'AbortError') return;
      resultadosVinos.innerHTML = '';
      mostrarError(error);
    }
  }

  function pintarVinos(pagina) {
    const vinos = Array.isArray(pagina?.data) ? pagina.data : [];
    if (vinos.length === 0) {
      resultadosVinos.innerHTML = '<p class="muted">Sin vinos para esa búsqueda.</p>';
      return;
    }

    resultadosVinos.innerHTML = vinos
      .map(
        (vino) => `
          <button type="button" class="search-result" data-vino="${vino.cod_vino}" data-nombre="${escapeHtml(vino.nombre_comercial)}" data-precio="${vino.precio_venta}">
            <span class="search-result-title">${escapeHtml(vino.nombre_comercial)}</span>
            <span class="search-result-meta">#${vino.cod_vino} · ${escapeHtml(tipoVino(vino.tipo))} · ${escapeHtml(String(vino.anada))} · ${escapeHtml(precio(vino.precio_venta))}</span>
          </button>
        `,
      )
      .join('');
  }

  function agregarRenglon(vino) {
    if (renglones.querySelector(`[data-cod="${vino.cod_vino}"]`)) {
      mostrarMensaje(`El vino #${vino.cod_vino} ya está en la venta.`);
      return;
    }

    ocultarError();
    renglones.insertAdjacentHTML('beforeend', filaRenglon(vino));
  }

  function mostrarError(error) {
    banner.hidden = false;
    banner.innerHTML = htmlError(error);
    banner.scrollIntoView?.({ block: 'nearest' });
  }

  function mostrarMensaje(mensaje) {
    banner.hidden = false;
    banner.innerHTML = `<p class="error-message">${escapeHtml(mensaje)}</p>`;
  }

  function ocultarError() {
    banner.hidden = true;
    banner.innerHTML = '';
  }
}

function plantilla() {
  return `
    <section class="page">
      <a class="back-link" href="#/">← Volver al catálogo</a>

      <div class="page-header">
        <div>
          <h1>Nueva venta</h1>
          <p class="muted">
            Los precios, descuentos y el total los calcula la base. Si no hay stock en la sala,
            se muestra el mensaje de la regla tal como lo devuelve la API.
          </p>
        </div>
        <span class="pill">Comprobante</span>
      </div>

      <div id="venta-error" class="error-banner" role="alert" hidden></div>

      <form id="venta-form" class="card form-card">
        <fieldset class="form-section">
          <legend>Cliente</legend>
          <div class="search-bar">
            <label class="field search-field">
              <span>Buscar por nombre o documento</span>
              <input id="cliente-q" type="search" placeholder="Ej.: Gomez" autocomplete="off" />
            </label>
            <button type="button" id="buscar-clientes" class="button button-secondary">Buscar</button>
          </div>
          <div id="clientes-resultados" class="search-results" aria-live="polite"></div>
          <p id="cliente-elegido" class="selected-item">Sin cliente seleccionado.</p>
        </fieldset>

        <div class="form-grid">
          <label class="field">
            <span>Sala (ID)</span>
            <input name="id_sala" type="number" min="1" step="1" required />
            <span class="field-hint">La API todavía no expone GET /salas; se ingresa el ID.</span>
          </label>
          <label class="field">
            <span>Fecha (opcional)</span>
            <input name="fecha" type="date" />
            <span class="field-hint">Si se omite, la base usa CURRENT_DATE.</span>
          </label>
        </div>

        <fieldset class="form-section">
          <legend>Vinos</legend>
          <div class="search-bar">
            <label class="field search-field">
              <span>Buscar vino por nombre</span>
              <input id="vino-q" type="search" placeholder="Ej.: Malbec" autocomplete="off" />
            </label>
            <button type="button" id="buscar-vinos" class="button button-secondary">Buscar</button>
          </div>
          <div id="vinos-resultados" class="search-results" aria-live="polite"></div>
          <div id="renglones" class="renglones"></div>
          <p class="muted">El precio unitario es informativo; la base recalcula precios, descuentos y totales.</p>
        </fieldset>

        <div class="form-actions">
          <button class="button" type="submit">Registrar venta</button>
          <a class="button button-secondary" href="#/">Cancelar</a>
        </div>
      </form>
    </section>
  `;
}

function filaRenglon(vino) {
  return `
    <div class="renglon-row" data-cod="${vino.cod_vino}">
      <div class="renglon-vino">
        <span class="search-result-title">${escapeHtml(vino.nombre)}</span>
        <span class="search-result-meta">#${vino.cod_vino} · ${escapeHtml(precio(vino.precio))} por unidad (precio de la API)</span>
      </div>
      <label class="field">
        <span>Cantidad</span>
        <input name="cantidad" type="number" min="1" step="1" value="1" required />
      </label>
      <button type="button" class="button button-secondary button-small" data-remove aria-label="Quitar vino">Quitar</button>
    </div>
  `;
}

function leerVenta(form, renglones, cliente) {
  const datos = {
    id_cliente: cliente.id_cliente,
    id_sala: aNumero(form.elements.namedItem('id_sala').value),
    renglones: Array.from(renglones.querySelectorAll('.renglon-row')).map((fila) => ({
      cod_vino: Number(fila.dataset.cod),
      cantidad: aNumero(fila.querySelector('[name="cantidad"]').value),
    })),
  };

  const fecha = form.elements.namedItem('fecha').value;
  if (fecha) datos.fecha = fecha;

  return datos;
}

function aNumero(valor) {
  const texto = String(valor ?? '').trim();
  if (texto === '') return null;
  const numero = Number(texto);
  return Number.isFinite(numero) ? numero : null;
}

function plantillaExito(comprobante) {
  const renglones = Array.isArray(comprobante.renglones) ? comprobante.renglones : [];

  return `
    <section class="page">
      <a class="back-link" href="#/">← Volver al catálogo</a>

      <div class="page-header">
        <div>
          <h1>Venta registrada</h1>
          <p class="muted">
            Comprobante N° ${escapeHtml(comprobante.nro_comprobante)} · ${escapeHtml(comprobante.fecha)}
            · cliente #${escapeHtml(comprobante.id_cliente)} · sala #${escapeHtml(comprobante.id_sala)}
          </p>
        </div>
        <span class="pill">Totales de la base</span>
      </div>

      <div class="grid">
        <section class="card">
          <h2>Renglones</h2>
          <div class="table-wrap">
            <table class="table">
              <thead>
                <tr>
                  <th scope="col">Vino</th>
                  <th scope="col" class="num">Cantidad</th>
                  <th scope="col" class="num">Precio unit.</th>
                  <th scope="col" class="num">Descuento</th>
                  <th scope="col" class="num">Subtotal</th>
                </tr>
              </thead>
              <tbody>
                ${renglones
                  .map(
                    (renglon) => `
                      <tr>
                        <td>${escapeHtml(renglon.nombre_comercial)} <span class="muted">#${renglon.cod_vino}</span></td>
                        <td class="num">${escapeHtml(numero(renglon.cantidad))}</td>
                        <td class="num">${escapeHtml(precio(renglon.precio_unitario))}</td>
                        <td class="num">${escapeHtml(precio(renglon.descuento))}</td>
                        <td class="num">${escapeHtml(precio(renglon.subtotal))}</td>
                      </tr>
                    `,
                  )
                  .join('')}
              </tbody>
            </table>
          </div>
        </section>

        <section class="card totals-card">
          <h2>Totales</h2>
          <dl class="totals">
            <div>
              <dt>Subtotal</dt>
              <dd>${escapeHtml(precio(comprobante.subtotal))}</dd>
            </div>
            <div>
              <dt>Descuento</dt>
              <dd>${escapeHtml(precio(comprobante.descuento))}</dd>
            </div>
            <div class="totals-final">
              <dt>Total</dt>
              <dd>${escapeHtml(precio(comprobante.total))}</dd>
            </div>
          </dl>
        </section>
      </div>

      <div class="form-actions">
        <a class="button" href="#/ventas/nueva">Registrar otra venta</a>
        <a class="button button-secondary" href="#/">Volver al catálogo</a>
      </div>
    </section>
  `;
}
