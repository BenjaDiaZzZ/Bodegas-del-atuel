import { api } from './client.js';

export function listarClientes({ page = 1, perPage = 8, q, tipo, idLocalidad } = {}, options = {}) {
  const params = new URLSearchParams();
  params.set('page', String(page));
  params.set('per_page', String(perPage));
  if (q) params.set('q', q);
  if (tipo) params.set('tipo', tipo);
  if (idLocalidad !== '' && idLocalidad != null) params.set('id_localidad', String(idLocalidad));

  return api.get(`/clientes?${params.toString()}`, options);
}
