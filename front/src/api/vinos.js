import { api } from './client.js';

export function listarVinos(
  { page = 1, perPage = 12, nombre, tipo, idCepa, cuitBodega, anada } = {},
  options = {},
) {
  const params = new URLSearchParams();
  params.set('page', String(page));
  params.set('per_page', String(perPage));
  if (nombre) params.set('nombre', nombre);
  if (tipo) params.set('tipo', tipo);
  if (idCepa !== '' && idCepa != null) params.set('id_cepa', String(idCepa));
  if (cuitBodega) params.set('cuit_bodega', cuitBodega);
  if (anada !== '' && anada != null) params.set('anada', String(anada));

  return api.get(`/vinos?${params.toString()}`, options);
}

export function obtenerVino(codVino, options = {}) {
  return api.get(`/vinos/${encodeURIComponent(codVino)}`, options);
}
