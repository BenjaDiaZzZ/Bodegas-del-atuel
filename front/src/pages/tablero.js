import { topVinos, ventasPorSala, vinosSinStock } from '../api/reportes.js';
import { htmlError } from '../utils/errors.js';
import { escapeHtml, numero, precio } from '../utils/format.js';

const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

export function renderTablero(outlet) {
  const controller = new AbortController();
  const rangoInicial = rangoTrimestre();

  outlet.innerHTML = plantilla(rangoInicial);

  const topEstado = outlet.querySelector('#top-estado');
  const topContenido = outlet.querySelector('#top-contenido');
  const ventasEstado = outlet.querySelector('#ventas-estado');
  const ventasContenido = outlet.querySelector('#ventas-contenido');
  const stockEstado = outlet.querySelector('#stock-estado');
  const stockContenido = outlet.querySelector('#stock-contenido');
  const rangoForm = outlet.querySelector('#rango');
  const stockForm = outlet.querySelector('#sala-form');

  rangoForm.addEventListener('submit', (event) => {
    event.preventDefault();
    cargarVentas(
      rangoForm.elements.namedItem('desde').value,
      rangoForm.elements.namedItem('hasta').value,
    );
  });

  stockForm.addEventListener('submit', (event) => {
    event.preventDefault();
    cargarStock(stockForm.elements.namedItem('id_sala').value);
  });

  cargarTop();
  cargarVentas(rangoInicial.desde, rangoInicial.hasta);
  cargarStock('1');

  return () => controller.abort();

  async function cargarTop() {
    estado(topEstado, 'Cargando ranking…');
    topContenido.innerHTML = '';
    try {
      const filas = await topVinos({ limite: 10 }, { signal: controller.signal });
      estado(topEstado, '');
      topContenido.innerHTML = tablaTop(filas);
    } catch (error) {
      if (error.name === 'AbortError') return;
      estado(topEstado, '');
      topContenido.innerHTML = bloqueError(error);
    }
  }

  async function cargarVentas(desde, hasta) {
    const rango = desde && hasta ? { desde, hasta } : rangoTrimestre();
    rangoForm.elements.namedItem('desde').value = rango.desde;
    rangoForm.elements.namedItem('hasta').value = rango.hasta;
    estado(ventasEstado, 'Cargando ventas…');
    ventasContenido.innerHTML = '';
    try {
      const filas = await ventasPorSala(rango, { signal: controller.signal });
      estado(ventasEstado, '');
      ventasContenido.innerHTML = grafico(filas, rango.desde, rango.hasta);
    } catch (error) {
      if (error.name === 'AbortError') return;
      estado(ventasEstado, '');
      ventasContenido.innerHTML = bloqueError(error);
    }
  }

  async function cargarStock(idSala) {
    estado(stockEstado, 'Consultando vinos sin stock…');
    stockContenido.innerHTML = '';
    try {
      const filas = await vinosSinStock(idSala, { signal: controller.signal });
      estado(stockEstado, '');
      stockContenido.innerHTML = tablaSinStock(filas, idSala);
    } catch (error) {
      if (error.name === 'AbortError') return;
      estado(stockEstado, '');
      stockContenido.innerHTML = bloqueError(error);
    }
  }

  function estado(elemento, texto) {
    elemento.textContent = texto;
    elemento.hidden = !texto;
  }
}

function plantilla(rango) {
  return `
    <section class="page">
      <div class="page-header">
        <div>
          <h1>Tablero</h1>
          <p class="muted">Ranking, ventas por sala y vinos sin stock.</p>
        </div>
        <span class="pill">Reportes</span>
      </div>

      <div class="grid">
        <section class="card">
          <h2>Top 10 vinos más vendidos</h2>
          <p id="top-estado" class="status">Cargando ranking…</p>
          <div id="top-contenido"></div>
        </section>

        <section class="card">
          <h2>Vinos sin stock en una sala</h2>
          <form id="sala-form" class="search-bar">
            <label class="field search-field">
              <span>Sala (ID)</span>
              <input name="id_sala" type="number" min="1" step="1" value="1" required />
            </label>
            <button class="button button-secondary" type="submit">Consultar</button>
          </form>
          <p id="stock-estado" class="status" hidden></p>
          <div id="stock-contenido"></div>
        </section>

        <section class="card card-wide">
          <h2>Ventas por sala · último trimestre</h2>
          <form id="rango" class="search-bar">
            <label class="field">
              <span>Desde</span>
              <input name="desde" type="date" required value="${escapeHtml(rango.desde)}" />
            </label>
            <label class="field">
              <span>Hasta</span>
              <input name="hasta" type="date" required value="${escapeHtml(rango.hasta)}" />
            </label>
            <button class="button button-secondary" type="submit">Actualizar</button>
          </form>
          <p id="ventas-estado" class="status">Cargando ventas…</p>
          <div id="ventas-contenido"></div>
        </section>
      </div>
    </section>
  `;
}

function tablaTop(filas) {
  if (!Array.isArray(filas) || filas.length === 0) {
    return '<p class="muted">Todavía no hay ventas para armar el ranking.</p>';
  }

  return `
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th scope="col">#</th>
            <th scope="col">Vino</th>
            <th scope="col" class="num">Botellas vendidas</th>
          </tr>
        </thead>
        <tbody>
          ${filas
            .map(
              (fila, indice) => `
                <tr>
                  <td>${indice + 1}</td>
                  <td>${escapeHtml(fila.nombre_comercial)} <span class="muted">#${fila.cod_vino}</span></td>
                  <td class="num">${escapeHtml(numero(fila.botellas_vendidas))}</td>
                </tr>
              `,
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
}

function grafico(filas, desde, hasta) {
  const periodo = `${escapeHtml(desde)} → ${escapeHtml(hasta)}`;

  if (!Array.isArray(filas) || filas.length === 0) {
    return `<p class="muted">Sin ventas entre ${periodo}.</p>`;
  }

  const maximo = Math.max(...filas.map((fila) => Number(fila.monto_total) || 0));

  return `
    <p class="muted">Período ${periodo} · ${filas.length} fila${filas.length === 1 ? '' : 's'}.</p>
    <div class="chart">
      ${filas
        .map((fila) => {
          const valor = Number(fila.monto_total) || 0;
          const ancho = maximo > 0 ? Math.max(2, Math.round((valor / maximo) * 100)) : 0;
          return `
            <div class="chart-row">
              <span class="chart-label">
                Sala #${fila.id_sala} · ${escapeHtml(mesCorto(fila.mes))}
                <span class="chart-sub">${escapeHtml(fila.localidad)} · ${escapeHtml(numero(fila.botellas_vendidas))} botellas</span>
              </span>
              <div class="chart-track"><div class="chart-bar" style="width:${ancho}%"></div></div>
              <span class="chart-value">${escapeHtml(precio(fila.monto_total))}</span>
            </div>
          `;
        })
        .join('')}
    </div>
    <p class="muted">Barras proporcionales al monto; el valor no se recalcula en el cliente.</p>
  `;
}

function tablaSinStock(filas, idSala) {
  const sala = escapeHtml(idSala);

  if (!Array.isArray(filas) || filas.length === 0) {
    return `<p class="muted">Sin vinos para transferir a la sala #${sala}.</p>`;
  }

  return `
    <p class="muted">Sala #${sala} · ${filas.length} vino${filas.length === 1 ? '' : 's'} con stock en depósito y sin stock en la sala.</p>
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th scope="col">Vino</th>
            <th scope="col" class="num">Stock sala</th>
            <th scope="col" class="num">Stock depósito</th>
          </tr>
        </thead>
        <tbody>
          ${filas
            .map(
              (fila) => `
                <tr>
                  <td>${escapeHtml(fila.nombre_comercial)} <span class="muted">#${fila.cod_vino}</span></td>
                  <td class="num">${escapeHtml(numero(fila.stock_sala))}</td>
                  <td class="num">${escapeHtml(numero(fila.stock_deposito))}</td>
                </tr>
              `,
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
}

function bloqueError(error) {
  return `<div class="error-banner" role="alert">${htmlError(error)}</div>`;
}

function rangoTrimestre() {
  const hoy = new Date();
  const desde = new Date(hoy.getFullYear(), hoy.getMonth() - 2, 1);
  return { desde: isoLocal(desde), hasta: isoLocal(hoy) };
}

function isoLocal(fecha) {
  const anio = fecha.getFullYear();
  const mes = String(fecha.getMonth() + 1).padStart(2, '0');
  const dia = String(fecha.getDate()).padStart(2, '0');
  return `${anio}-${mes}-${dia}`;
}

function mesCorto(iso) {
  const [anio, mes] = String(iso ?? '').split('-');
  const indice = Number(mes) - 1;
  if (!anio || !MESES[indice]) return String(iso ?? '');
  return `${MESES[indice]} ${anio}`;
}
