const formatoPrecio = new Intl.NumberFormat('es-AR', {
  style: 'currency',
  currency: 'ARS',
  maximumFractionDigits: 2,
});

const formatoNumero = new Intl.NumberFormat('es-AR', {
  maximumFractionDigits: 2,
});

const ENTIDADES = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

export function precio(valor) {
  return formatoPrecio.format(Number(valor) || 0);
}

export function numero(valor) {
  return formatoNumero.format(Number(valor) || 0);
}

export function tipoVino(valor) {
  if (!valor) return '';
  return valor.charAt(0).toUpperCase() + valor.slice(1).replace(/_/g, ' ');
}

export function presentacion(ml) {
  const mililitros = Number(ml) || 0;
  if (mililitros >= 1000) {
    return `${formatoNumero.format(mililitros / 1000)} L`;
  }
  return `${formatoNumero.format(mililitros)} ml`;
}

export function escapeHtml(valor) {
  return String(valor ?? '').replace(/[&<>"']/g, (caracter) => ENTIDADES[caracter]);
}
