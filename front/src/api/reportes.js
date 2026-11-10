import { api } from './client.js';

export function topVinos({ limite = 10 } = {}, options = {}) {
  const params = new URLSearchParams();
  params.set('limite', String(limite));
  return api.get(`/reportes/top-vinos?${params.toString()}`, options);
}

export function ventasPorSala({ desde, hasta } = {}, options = {}) {
  const params = new URLSearchParams();
  if (desde) params.set('desde', desde);
  if (hasta) params.set('hasta', hasta);
  const query = params.toString();
  return api.get(`/reportes/ventas-por-sala${query ? `?${query}` : ''}`, options);
}

export function vinosSinStock(idSala, options = {}) {
  const params = new URLSearchParams();
  params.set('id_sala', String(idSala));
  return api.get(`/reportes/vinos-sin-stock?${params.toString()}`, options);
}
