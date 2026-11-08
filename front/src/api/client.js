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

async function pedir(path, { signal } = {}) {
  const respuesta = await fetch(`${baseUrl}${path}`, {
    headers: { Accept: 'application/json' },
    signal,
  });

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
};
