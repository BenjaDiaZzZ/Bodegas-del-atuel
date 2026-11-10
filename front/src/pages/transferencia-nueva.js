import { listarVinos } from '../api/vinos.js';
import {
  agregarRenglonTransferencia,
  crearTransferencia,
  procesarTransferencia,
  terminarTransferencia,
} from '../api/transferencias.js';
import { htmlError } from '../utils/errors.js';
import { escapeHtml, numero, precio, tipoVino } from '../utils/format.js';

const VINOS_PER_PAGE = 6;

export function renderTransferenciaNueva(outlet) {
  const controller = new AbortController();
  let transferencia = null;
  let vinoElegido = null;

  outlet.innerHTML = plantilla();

  const banner = outlet.querySelector('#transferencia-error');
  const contenido = outlet.querySelector('#transferencia-contenido');

  pintarContenido();

  return () => controller.abort();

  function pintarContenido() {
    if (!transferencia) {
      contenido.innerHTML = plantillaCreacion();
      contenido.querySelector('#crear-transferencia').addEventListener('submit', crear);
      return;
    }

    contenido.innerHTML = plantillaDetalle(transferencia);

    const terminar = contenido.querySelector('#terminar');
    if (terminar) {
      terminar.addEventListener('click', () =>
        ejecutar(terminar, () => terminarTransferencia(transferencia.nro_solicitud, { signal: controller.signal })),
      );
    }

    const procesar = contenido.querySelector('#procesar');
    if (procesar) {
      procesar.addEventListener('click', () =>
        ejecutar(procesar, () => procesarTransferencia(transferencia.nro_solicitud, { signal: controller.signal })),
      );
    }

    if (transferencia.estado === 'en_confeccion') {
      conectarCargaDeRenglones();
    }
  }

  async function crear(event) {
    event.preventDefault();
    ocultarError();

    const form = event.currentTarget;
    const boton = form.querySelector('button[type="submit"]');
    const textoOriginal = boton.textContent;
    boton.disabled = true;
    boton.textContent = 'Creando…';

    try {
      transferencia = await crearTransferencia(
        { idSala: aNumero(form.elements.namedItem('id_sala').value) },
        { signal: controller.signal },
      );
      vinoElegido = null;
      pintarContenido();
    } catch (error) {
      if (error.name === 'AbortError') return;
      mostrarError(error);
      boton.disabled = false;
      boton.textContent = textoOriginal;
    }
  }

  function conectarCargaDeRenglones() {
    const qVino = contenido.querySelector('#vino-q');
    const resultados = contenido.querySelector('#vinos-resultados');
    const agregar = contenido.querySelector('#agregar-renglon');

    contenido.querySelector('#buscar-vinos').addEventListener('click', buscarVinos);
    qVino.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter') return;
      event.preventDefault();
      buscarVinos();
    });

    resultados.addEventListener('click', (event) => {
      const elegido = event.target.closest('button[data-vino]');
      if (!elegido) return;

      vinoElegido = {
        cod_vino: Number(elegido.dataset.vino),
        nombre: elegido.dataset.nombre,
      };

      const seleccionado = contenido.querySelector('#vino-elegido');
      seleccionado.classList.add('selected-item-ok');
      seleccionado.textContent = `Vino: ${vinoElegido.nombre} (#${vinoElegido.cod_vino})`;
      agregar.disabled = false;
    });

    agregar.addEventListener('click', () => {
      if (!vinoElegido) return;
      const cantidad = aNumero(contenido.querySelector('#cantidad-renglon').value);
      ejecutar(agregar, () =>
        agregarRenglonTransferencia(
          transferencia.nro_solicitud,
          { codVino: vinoElegido.cod_vino, cantidad },
          { signal: controller.signal },
        ),
      );
    });

    async function buscarVinos() {
      const q = qVino.value.trim();
      resultados.innerHTML = '<p class="muted">Buscando vinos…</p>';
      try {
        const pagina = await listarVinos({ nombre: q, perPage: VINOS_PER_PAGE }, { signal: controller.signal });
        pintarVinos(pagina);
      } catch (error) {
        if (error.name === 'AbortError') return;
        resultados.innerHTML = '';
        mostrarError(error);
      }
    }

    function pintarVinos(pagina) {
      const vinos = Array.isArray(pagina?.data) ? pagina.data : [];
      if (vinos.length === 0) {
        resultados.innerHTML = '<p class="muted">Sin vinos para esa búsqueda.</p>';
        return;
      }

      resultados.innerHTML = vinos
        .map(
          (vino) => `
            <button type="button" class="search-result" data-vino="${vino.cod_vino}" data-nombre="${escapeHtml(vino.nombre_comercial)}">
              <span class="search-result-title">${escapeHtml(vino.nombre_comercial)}</span>
              <span class="search-result-meta">#${vino.cod_vino} · ${escapeHtml(tipoVino(vino.tipo))} · ${escapeHtml(String(vino.anada))} · ${escapeHtml(precio(vino.precio_venta))}</span>
            </button>
          `,
        )
        .join('');
    }
  }

  async function ejecutar(boton, accion) {
    ocultarError();
    const textoOriginal = boton.textContent;
    boton.disabled = true;
    boton.textContent = 'Procesando…';

    try {
      transferencia = await accion();
      vinoElegido = null;
      pintarContenido();
    } catch (error) {
      if (error.name === 'AbortError') return;
      mostrarError(error);
      boton.disabled = false;
      boton.textContent = textoOriginal;
    }
  }

  function mostrarError(error) {
    banner.hidden = false;
    banner.innerHTML = htmlError(error);
    banner.scrollIntoView?.({ block: 'nearest' });
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
          <h1>Transferencias</h1>
          <p class="muted">
            Creá la transferencia, cargá renglones y avanzá de estado. La base valida
            las transiciones y el stock del depósito.
          </p>
        </div>
        <span class="pill">Depósito → sala</span>
      </div>

      <div id="transferencia-error" class="error-banner" role="alert" hidden></div>
      <div id="transferencia-contenido"></div>
    </section>
  `;
}

function plantillaCreacion() {
  return `
    <section class="card form-card">
      <h2>Nueva transferencia</h2>
      <p class="muted">Elegí la sala destino. La fecha de confección la fija la base (RN-11).</p>
      <form id="crear-transferencia" class="form-grid">
        <label class="field">
          <span>Sala destino (ID)</span>
          <input name="id_sala" type="number" min="1" step="1" required />
        </label>
        <div class="form-actions">
          <button class="button" type="submit">Crear transferencia</button>
        </div>
      </form>
    </section>
  `;
}

function plantillaDetalle(transferencia) {
  const estado = transferencia.estado;
  const enConfeccion = estado === 'en_confeccion';
  const terminado = estado === 'terminado';
  const procesado = estado === 'procesado';

  return `
    <div class="grid">
      <section class="card">
        <h2>Datos</h2>
        <dl class="totals">
          <div>
            <dt>N° solicitud</dt>
            <dd>${escapeHtml(transferencia.nro_solicitud)}</dd>
          </div>
          <div>
            <dt>Sala destino</dt>
            <dd>#${escapeHtml(transferencia.id_sala)}</dd>
          </div>
          <div>
            <dt>Fecha de confección</dt>
            <dd>${escapeHtml(transferencia.fecha_confeccion)}</dd>
          </div>
          <div>
            <dt>Estado</dt>
            <dd>${escapeHtml(etiquetaEstado(estado))}</dd>
          </div>
        </dl>
      </section>

      <section class="card">
        <h2>Renglones</h2>
        ${tablaRenglones(transferencia.renglones)}
      </section>
    </div>

    <section class="card form-card">
      <h2>Acciones</h2>
      ${enConfeccion ? bloqueAgregarRenglon() : `<p class="muted">${terminado ? 'La transferencia está terminada: ya no se pueden editar renglones.' : 'La transferencia fue procesada: el stock ya se movió a la sala.'}</p>`}

      <div class="form-actions">
        <button id="terminar" class="button" ${enConfeccion ? '' : 'disabled'}>Terminar transferencia</button>
        <button id="procesar" class="button" ${terminado ? '' : 'disabled'}>Procesar transferencia</button>
        ${procesado ? '<a class="button button-secondary" href="#/transferencias/nueva">Nueva transferencia</a>' : ''}
      </div>

      ${procesado ? '<p class="status status-ok">Transferencia procesada: el stock pasó del depósito a la sala.</p>' : ''}
    </section>
  `;
}

function bloqueAgregarRenglon() {
  return `
    <div class="search-bar">
      <label class="field search-field">
        <span>Buscar vino por nombre</span>
        <input id="vino-q" type="search" placeholder="Ej.: Malbec" autocomplete="off" />
      </label>
      <button type="button" id="buscar-vinos" class="button button-secondary">Buscar</button>
    </div>
    <div id="vinos-resultados" class="search-results" aria-live="polite"></div>
    <p id="vino-elegido" class="selected-item">Sin vino seleccionado.</p>
    <div class="search-bar">
      <label class="field search-field">
        <span>Cantidad</span>
        <input id="cantidad-renglon" type="number" min="1" step="1" value="1" />
      </label>
      <button type="button" id="agregar-renglon" class="button button-secondary" disabled>Agregar renglón</button>
    </div>
  `;
}

function tablaRenglones(renglones) {
  if (!Array.isArray(renglones) || renglones.length === 0) {
    return '<p class="muted">Sin renglones cargados.</p>';
  }

  return `
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th scope="col">Vino</th>
            <th scope="col" class="num">Cantidad</th>
          </tr>
        </thead>
        <tbody>
          ${renglones
            .map(
              (renglon) => `
                <tr>
                  <td>${escapeHtml(renglon.nombre_comercial)} <span class="muted">#${renglon.cod_vino}</span></td>
                  <td class="num">${escapeHtml(numero(renglon.cantidad))}</td>
                </tr>
              `,
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
}

function etiquetaEstado(estado) {
  if (estado === 'en_confeccion') return 'En confección';
  if (estado === 'terminado') return 'Terminado';
  if (estado === 'procesado') return 'Procesado';
  return estado;
}

function aNumero(valor) {
  const texto = String(valor ?? '').trim();
  if (texto === '') return null;
  const numero = Number(texto);
  return Number.isFinite(numero) ? numero : null;
}
