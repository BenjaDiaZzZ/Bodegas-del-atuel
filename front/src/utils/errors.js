import { escapeHtml } from './format.js';

export function htmlError(error) {
  const partes = [`<p class="error-message">${escapeHtml(error.message)}</p>`];
  const meta = [];

  if (error.status) meta.push(`HTTP ${error.status}`);
  if (error.codigo) meta.push(`código ${error.codigo}`);
  if (error.regla) meta.push(`regla ${error.regla}`);
  if (meta.length > 0) partes.push(`<p class="error-meta">${escapeHtml(meta.join(' · '))}</p>`);

  if (Array.isArray(error.detalle) && error.detalle.length > 0) {
    const items = error.detalle.map((item) => {
      if (item && typeof item === 'object') {
        const campo = item.campo ?? item.ubicacion ?? '';
        const mensaje = item.mensaje ?? item.message ?? JSON.stringify(item);
        return `<li>${campo ? `<strong>${escapeHtml(campo)}:</strong> ` : ''}${escapeHtml(mensaje)}</li>`;
      }
      return `<li>${escapeHtml(item)}</li>`;
    });
    partes.push(`<ul class="error-detail">${items.join('')}</ul>`);
  } else if (error.detalle) {
    const detalle = typeof error.detalle === 'string' ? error.detalle : JSON.stringify(error.detalle);
    partes.push(`<p class="error-meta">${escapeHtml(detalle)}</p>`);
  }

  return partes.join('');
}
