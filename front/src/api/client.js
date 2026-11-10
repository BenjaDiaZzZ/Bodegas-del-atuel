const baseUrl = (import.meta.env.VITE_API_URL || '/api').replace(/\/+$/, '');

export class ApiError extends Error {
  constructor(datos, status) {
    super(datos?.mensaje || `Error HTTP ${status}`);
    this.name = 'ApiError';
    this.status = status;
    this.codigo = datos?.codigo ?? null;
    this.detalle = datos?.detalle ?? null;
    this.regla = datos?.regla ?? null;
  }
}

async function pedir(path, { signal, method = 'GET', body } = {}) {
  const headers = { Accept: 'application/json' };
  let cuerpo;

  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    cuerpo = JSON.stringify(body);
  }

  const respuesta = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: cuerpo,
    signal,
  });

  if (respuesta.status === 204) return null;

  const texto = await respuesta.text();
  let datos = null;
  if (texto) {
    try {
      datos = JSON.parse(texto);
    } catch {
      datos = { mensaje: texto };
    }
  }

  if (!respuesta.ok) {
    throw new ApiError(datos, respuesta.status);
  }

  return datos;
}

export const api = {
  get: pedir,
  post: (path, body, options = {}) => pedir(path, { ...options, method: 'POST', body }),
  put: (path, body, options = {}) => pedir(path, { ...options, method: 'PUT', body }),
};
