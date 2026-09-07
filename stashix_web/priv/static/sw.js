const CACHE = "stashix-v1"
const STATIC = ["/assets/app.css", "/assets/app.js"]

self.addEventListener("install", e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(STATIC)).then(() => self.skipWaiting())
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

  // Never intercept WebSocket upgrades, LiveView socket, or non-GET
  if (e.request.method !== "GET") return
  if (url.pathname.startsWith("/live") || url.pathname.startsWith("/socket")) return

  // Cache-first for versioned static assets
  if (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/icons/")) {
    e.respondWith(
      caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
        const clone = res.clone()
        caches.open(CACHE).then(c => c.put(e.request, clone))
        return res
      }))
    )
    return
  }

  // Network-first for navigation and everything else
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  )
})
