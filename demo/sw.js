const CACHE = 'starward-web-v1';
const WASM_PATTERN = /\/index\.wasm$/;

function cleanResponse(response) {
  const headers = new Headers(response.headers);
  headers.delete('content-encoding');
  headers.delete('content-length');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: headers
  });
}

async function store(cache, request, response) {
  if (!response || !response.ok) return response;
  const clean = cleanResponse(response);
  await cache.put(request, clean.clone());
  return clean;
}

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith('starward-') && key !== CACHE).map((key) => caches.delete(key)));
    await self.clients.claim();
    // 首次访问时 wasm 通常还在浏览器 HTTP 缓存里，只读取、不重复下载。
    try {
      const cache = await caches.open(CACHE);
      const found = await cache.match('./index.wasm', { ignoreSearch: true });
      if (!found) {
        const request = new Request('./index.wasm', { cache: 'only-if-cached', mode: 'same-origin' });
        const response = await fetch(request);
        await store(cache, request, response);
      }
    } catch (error) {
      // HTTP 缓存已过期时留给下一次加载，不在这里额外下载 10 MB。
    }
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || request.headers.has('range')) return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (WASM_PATTERN.test(url.pathname)) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(request, { ignoreSearch: true });
      if (cached) return cached;
      const response = await fetch(request);
      return store(cache, request, response);
    })());
    return;
  }

  if (/\/index\.(pck|js|html)$/.test(url.pathname)) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      try {
        const response = await fetch(request);
        await store(cache, request, response.clone());
        return response;
      } catch (error) {
        const cached = await cache.match(request, { ignoreSearch: true });
        if (cached) return cached;
        throw error;
      }
    })());
  }
});
