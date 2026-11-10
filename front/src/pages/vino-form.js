import { actualizarVino, crearVino, obtenerVino } from '../api/vinos.js';
import { navigate } from '../router.js';
import { escapeHtml } from '../utils/format.js';
import { htmlError } from '../utils/errors.js';

const TIPOS = ['tinto', 'blanco', 'rosado', 'espumante'];
const PRESENTACIONES = [375, 750, 1500];

export function renderVinoForm(outlet, { codVino } = {}) {
  if (codVino == null) {
    pintar(null);
    return () => {};
  }

  const controller = new AbortController();
  outlet.innerHTML = `<section class="page"><p class="status" role="status">Cargando vino…</p></section>`;

  cargar();

  async function cargar() {
    try {
      const vino = await obtenerVino(codVino, { signal: controller.signal });
      pintar(vino);
    } catch (error) {
      if (error.name === 'AbortError') return;
      outlet.innerHTML = `
        <section class="page">
          <a class="back-link" href="#/">← Volver al catálogo</a>
          <div class="error-banner" role="alert">
            <p class="error-message">${escapeHtml(error.message)}</p>
          </div>
        </section>
      `;
    }
  }

  return () => controller.abort();

  function pintar(vino) {
    const editando = Boolean(vino);
    const datos = vino ?? {};
    const composicion = Array.isArray(datos.composicion) && datos.composicion.length > 0 ? datos.composicion : [{}];

    outlet.innerHTML = plantilla(datos, editando);

    const form = outlet.querySelector('#vino-form');
    const banner = outlet.querySelector('#form-error');
    const contenedor = outlet.querySelector('#composicion');
    const suma = outlet.querySelector('#suma');
    const boton = form.querySelector('button[type="submit"]');

    composicion.forEach((item) => contenedor.insertAdjacentHTML('beforeend', filaComposicion(item)));
    actualizarSuma();

    contenedor.addEventListener('input', actualizarSuma);
    contenedor.addEventListener('click', (event) => {
      const quitar = event.target.closest('button[data-remove]');
      if (!quitar) return;

      quitar.closest('.composition-row').remove();
      if (!contenedor.querySelector('.composition-row')) {
        contenedor.insertAdjacentHTML('beforeend', filaComposicion());
      }
      actualizarSuma();
    });

    outlet.querySelector('#agregar-cepa').addEventListener('click', () => {
      contenedor.insertAdjacentHTML('beforeend', filaComposicion());
      actualizarSuma();
    });

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      ocultarError();

      const enviado = leerFormulario(form, contenedor);
      const textoOriginal = boton.textContent;
      boton.disabled = true;
      boton.textContent = editando ? 'Guardando…' : 'Creando…';

      try {
        const guardado = editando
          ? await actualizarVino(vino.cod_vino, enviado)
          : await crearVino(enviado);
        navigate(`/vinos/${guardado.cod_vino}`);
      } catch (error) {
        if (error.name === 'AbortError') return;
        mostrarError(error);
        boton.disabled = false;
        boton.textContent = textoOriginal;
      }
    });

    function actualizarSuma() {
      const total = leerComposicion(contenedor).reduce(
        (acumulado, item) => acumulado + (Number.isFinite(item.porcentaje) ? item.porcentaje : 0),
        0,
      );
      suma.textContent = `Suma parcial: ${total} %`;
      suma.classList.toggle('composition-sum-ok', total === 100);
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
}

function plantilla(datos, editando) {
  const presentaciones = PRESENTACIONES.includes(Number(datos.presentacion_ml))
    ? PRESENTACIONES
    : [...PRESENTACIONES, Number(datos.presentacion_ml)].filter((valor) => Number.isFinite(valor));
  const maridajes = (datos.maridajes ?? []).map((item) => item.id_maridaje).join(', ');

  return `
    <section class="page">
      <a class="back-link" href="${editando ? `#/vinos/${encodeURIComponent(datos.cod_vino)}` : '#/'}">← Volver</a>

      <div class="page-header">
        <div>
          <h1>${editando ? 'Editar vino' : 'Nuevo vino'}</h1>
          <p class="muted">
            ${editando
              ? `Modificá los datos de <strong>${escapeHtml(datos.nombre_comercial)}</strong>.`
              : 'La composición de cepas debe sumar 100 %.'}
          </p>
        </div>
        <span class="pill">${editando ? `Vino ${escapeHtml(datos.cod_vino)}` : 'Alta'}</span>
      </div>

      <div id="form-error" class="error-banner" role="alert" hidden></div>

      <form id="vino-form" class="card form-card">
        <div class="form-grid">
          <label class="field field-wide">
            <span>Nombre comercial</span>
            <input name="nombre_comercial" type="text" maxlength="120" required value="${escapeHtml(datos.nombre_comercial ?? '')}" />
          </label>

          <label class="field">
            <span>Tipo</span>
            <select name="tipo" required>
              ${TIPOS.map(
                (tipo) => `<option value="${tipo}"${datos.tipo === tipo ? ' selected' : ''}>${tipo}</option>`,
              ).join('')}
            </select>
          </label>

          <label class="field">
            <span>Añada</span>
            <input name="anada" type="number" min="1900" max="2100" step="1" required value="${escapeHtml(datos.anada ?? '')}" />
          </label>

          <label class="field">
            <span>Presentación</span>
            <select name="presentacion_ml" required>
              ${presentaciones
                .map(
                  (ml) => `<option value="${ml}"${Number(datos.presentacion_ml) === ml ? ' selected' : ''}>${ml} ml</option>`,
                )
                .join('')}
            </select>
          </label>

          <label class="field">
            <span>Graduación (% vol.)</span>
            <input name="graduacion" type="number" min="5" max="20" step="0.1" required value="${escapeHtml(datos.graduacion ?? '')}" />
          </label>

          <label class="field">
            <span>Precio de venta</span>
            <input name="precio_venta" type="number" min="0.01" step="0.01" required value="${escapeHtml(datos.precio_venta ?? '')}" />
          </label>

          <label class="field">
            <span>CUIT de la bodega</span>
            <input name="cuit_bodega" type="text" inputmode="numeric" maxlength="11" pattern="[0-9]{11}" required value="${escapeHtml(datos.cuit_bodega ?? '')}" />
          </label>
        </div>

        <fieldset class="composition-fieldset">
          <legend>Composición de cepas</legend>
          <p class="muted">La suma debe ser exactamente 100.</p>
          <div id="composicion" class="composition"></div>
          <button type="button" id="agregar-cepa" class="button button-secondary button-small">Agregar cepa</button>
          <p id="suma" class="muted composition-sum" aria-live="polite"></p>
        </fieldset>

        <label class="field">
          <span>Maridajes (IDs separados por coma, opcional)</span>
          <input name="maridajes" type="text" placeholder="Ej.: 1, 3" value="${escapeHtml(maridajes)}" />
        </label>

        <div class="form-actions">
          <button class="button" type="submit">${editando ? 'Guardar cambios' : 'Crear vino'}</button>
          <a class="button button-secondary" href="${editando ? `#/vinos/${encodeURIComponent(datos.cod_vino)}` : '#/'}">Cancelar</a>
        </div>
      </form>
    </section>
  `;
}

function filaComposicion(item = {}) {
  return `
    <div class="composition-row">
      <label class="field">
        <span>Cepa (ID)</span>
        <input name="id_cepa" type="number" min="1" step="1" required value="${escapeHtml(item.id_cepa ?? '')}" />
      </label>
      <label class="field">
        <span>Porcentaje</span>
        <input name="porcentaje" type="number" min="0" max="100" step="0.01" required value="${escapeHtml(item.porcentaje ?? '')}" />
      </label>
      <button type="button" class="button button-secondary button-small" data-remove aria-label="Quitar cepa">Quitar</button>
    </div>
  `;
}

function leerFormulario(form, contenedor) {
  const datos = {
    nombre_comercial: campo(form, 'nombre_comercial').value.trim(),
    tipo: campo(form, 'tipo').value,
    anada: aNumero(campo(form, 'anada').value),
    presentacion_ml: aNumero(campo(form, 'presentacion_ml').value),
    graduacion: aNumero(campo(form, 'graduacion').value),
    precio_venta: aNumero(campo(form, 'precio_venta').value),
    cuit_bodega: campo(form, 'cuit_bodega').value.trim(),
    composicion: leerComposicion(contenedor),
    maridajes: leerIds(campo(form, 'maridajes').value),
  };

  return datos;
}

function campo(form, nombre) {
  return form.elements.namedItem(nombre);
}

function leerComposicion(contenedor) {
  return Array.from(contenedor.querySelectorAll('.composition-row')).map((fila) => ({
    id_cepa: aNumero(fila.querySelector('[name="id_cepa"]').value),
    porcentaje: aNumero(fila.querySelector('[name="porcentaje"]').value),
  }));
}

function leerIds(texto) {
  return String(texto ?? '')
    .split(',')
    .map((parte) => parte.trim())
    .filter(Boolean)
    .map((parte) => Number.parseInt(parte, 10))
    .filter((valor) => Number.isFinite(valor) && valor > 0);
}

function aNumero(valor) {
  const texto = String(valor ?? '').trim();
  if (texto === '') return null;
  const numero = Number(texto);
  return Number.isFinite(numero) ? numero : null;
}
