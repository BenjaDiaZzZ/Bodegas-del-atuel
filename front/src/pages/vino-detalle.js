import { obtenerVino } from '../api/vinos.js';
import { escapeHtml, numero, precio, presentacion, tipoVino } from '../utils/format.js';

export function renderVinoDetalle(outlet, codVino) {
  const controller = new AbortController();
  outlet.innerHTML = `<section class="page"><p class="status" role="status">Cargando vino…</p></section>`;

  cargar();

  async function cargar() {
    try {
      const vino = await obtenerVino(codVino, { signal: controller.signal });
      outlet.innerHTML = plantilla(vino);
    } catch (error) {
      if (error.name === 'AbortError') return;
      outlet.innerHTML = `
        <section class="page">
          <a class="back-link" href="#/">← Volver al catálogo</a>
          <p class="status status-error">${escapeHtml(error.message)}</p>
        </section>
      `;
    }
  }

  return () => controller.abort();
}

function plantilla(vino) {
  const cuit = encodeURIComponent(vino.cuit_bodega);
  const anada = encodeURIComponent(vino.anada);

  return `
    <section class="page">
      <a class="back-link" href="#/">← Volver al catálogo</a>

      <div class="page-header">
        <div>
          <h1>${escapeHtml(vino.nombre_comercial)}</h1>
          <p class="muted">
            <a class="link-muted" href="#/?cuit_bodega=${cuit}">${escapeHtml(vino.bodega || vino.cuit_bodega)}</a>
            · ${escapeHtml(tipoVino(vino.tipo))}
            · <a class="link-muted" href="#/?anada=${anada}">${escapeHtml(vino.anada)}</a>
            · ${escapeHtml(presentacion(vino.presentacion_ml))}
            · ${escapeHtml(numero(vino.graduacion))} % vol.
          </p>
        </div>
        <div class="price-box">
          <span class="price-label">Precio de venta</span>
          <span class="price">${escapeHtml(precio(vino.precio_venta))}</span>
          <a class="button button-small" href="#/vinos/${encodeURIComponent(vino.cod_vino)}/editar">Editar vino</a>
        </div>
      </div>

      <div class="grid">
        <section class="card">
          <h2>Composición</h2>
          ${listaComposicion(vino.composicion)}
        </section>

        <section class="card">
          <h2>Maridajes</h2>
          ${listaMaridajes(vino.maridajes)}
        </section>

        <section class="card">
          <h2>Stock</h2>
          ${stock(vino.stock)}
        </section>
      </div>
    </section>
  `;
}

function listaComposicion(composicion) {
  if (!Array.isArray(composicion) || composicion.length === 0) {
    return '<p class="muted">Sin composición informada.</p>';
  }

  const total = composicion.reduce((a, i) => a + Number(i.porcentaje || 0), 0);
  return `
    <div class="chart">
      ${composicion
        .map(
          (item) => {
            const porcentaje = Number(item.porcentaje || 0);
            const ancho = total > 0 ? Math.max(2, Math.round((porcentaje / total) * 100)) : 0;
            return `
              <div class="chart-row">
                <div class="chart-label">
                  <a class="link" href="#/?id_cepa=${encodeURIComponent(item.id_cepa)}">${escapeHtml(item.nombre || `Cepa ${item.id_cepa}`)}</a>
                </div>
                <div class="chart-track">
                  <div class="chart-bar" style="width:${ancho}%"></div>
                </div>
                <div class="chart-value">${escapeHtml(numero(porcentaje))} %</div>
              </div>
            `;
          },
        )
        .join('')}
    </div>
    <p class="muted" style="margin-top:8px">Total ${escapeHtml(numero(total))} %</p>
  `;
}

function listaMaridajes(maridajes) {
  if (!Array.isArray(maridajes) || maridajes.length === 0) {
    return '<p class="muted">Sin maridajes sugeridos.</p>';
  }

  return `
    <ul class="simple-list">
      ${maridajes
        .map(
          (item) => `
            <li>
              <span>${escapeHtml(item.nombre || `Maridaje ${item.id_maridaje}`)}</span>
              ${item.temperatura_servicio != null ? `<span class="badge">${escapeHtml(numero(item.temperatura_servicio))} °C</span>` : ''}
            </li>
          `,
        )
        .join('')}
    </ul>
  `;
}

function stock(datos) {
  if (!datos) {
    return '<p class="muted">Sin stock informado.</p>';
  }

  return `
    <dl class="stock-grid">
      <div>
        <dt>Depósito</dt>
        <dd>${escapeHtml(numero(datos.deposito))}</dd>
      </div>
      <div>
        <dt>Salas</dt>
        <dd>${escapeHtml(numero(datos.salas))}</dd>
      </div>
      <div class="stock-total">
        <dt>Total</dt>
        <dd>${escapeHtml(numero(datos.total))}</dd>
      </div>
    </dl>
  `;
}
