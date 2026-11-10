import { api } from './client.js';

export function crearComprobante(datos, options = {}) {
  return api.post('/comprobantes', datos, options);
}
