const noCache = new URLSearchParams(self.location.search).has("nocache")

const CACHE = "stashix-v1"
const STATIC = ["/assets/app.css", "/assets/app.js"]

self.addEventListener("install", e => {
  e.waitUntil(
    noCache
      ? self.skipWaiting()
      : caches.open(CACHE).then(c => c.addAll(STATIC)).then(() => self.skipWaiting())
  )
})

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url)

  if (e.request.method !== "GET") return
  if (url.pathname.startsWith("/live") || url.pathname.startsWith("/socket")) return

  if (!noCache && (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/icons/"))) {
    e.respondWith(
      caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
        const clone = res.clone()
        caches.open(CACHE).then(c => c.put(e.request, clone))
        return res
      }))
    )
    return
  }

  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  )
})
