/* LeafNote service worker: app shell + static assets.
 * Note bodies are cached in localStorage by the app, not here.
 */
const VERSION = 'leafnote-v1'
const SCOPE = self.registration.scope
const CORE = ['', 'index.html', 'manifest.webmanifest', 'icons/icon.svg', 'icons/icon-192.png', 'icons/icon-512.png']
  .map((path) => new URL(path, SCOPE).toString())

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(VERSION).then((cache) =>
      Promise.allSettled(CORE.map((url) => cache.add(new Request(url, { cache: 'reload' }))))
    )
  )
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== VERSION).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener('fetch', (event) => {
  const request = event.request
  if (request.method !== 'GET') return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone()
            caches.open(VERSION).then((cache) => cache.put(new URL('index.html', SCOPE).toString(), copy))
          }
          return response
        })
        .catch(async () => {
          const cache = await caches.open(VERSION)
          return (
            (await cache.match(new URL('index.html', SCOPE).toString())) ||
            (await cache.match(new URL('', SCOPE).toString())) ||
            new Response('离线状态，请联网后重试。', {
              status: 503,
              headers: { 'Content-Type': 'text/plain; charset=utf-8' }
            })
          )
        })
    )
    return
  }

  if (url.pathname.endsWith('/sw.js')) return

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached
      return fetch(request).then((response) => {
        if (response && response.ok && (response.type === 'basic' || response.type === 'default')) {
          const copy = response.clone()
          caches.open(VERSION).then((cache) => cache.put(request, copy))
        }
        return response
      })
    })
  )
})
