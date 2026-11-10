import { api } from './client.js';

export function crearTransferencia({ idSala }, options = {}) {
  return api.post('/transferencias', { id_sala: idSala }, options);
}

export function agregarRenglonTransferencia(nro, { codVino, cantidad }, options = {}) {
  return api.post(
    `/transferencias/${encodeURIComponent(nro)}/renglones`,
    { cod_vino: codVino, cantidad },
    options,
  );
}

export function terminarTransferencia(nro, options = {}) {
  return api.post(`/transferencias/${encodeURIComponent(nro)}/terminar`, undefined, options);
}

export function procesarTransferencia(nro, options = {}) {
  return api.post(`/transferencias/${encodeURIComponent(nro)}/procesar`, undefined, options);
}
