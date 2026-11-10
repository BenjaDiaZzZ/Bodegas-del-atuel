export function readRoute(hash = window.location.hash) {
  const raw = hash.replace(/^#/, '') || '/';
  const [pathname, search = ''] = raw.split('?');

  return {
    pathname: pathname || '/',
    query: new URLSearchParams(search),
  };
}

export function navigate(pathname, params = new URLSearchParams()) {
  const search = params.toString();
  const hash = `#${pathname}${search ? `?${search}` : ''}`;

  if (window.location.hash === hash) {
    window.dispatchEvent(new HashChangeEvent('hashchange'));
    return;
  }

  window.location.hash = hash;
}

export function onRouteChange(callback) {
  window.addEventListener('hashchange', callback);
  callback();
}
