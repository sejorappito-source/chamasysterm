// Harambee app shell cache.
//
// Deliberately simple: caches the static shell (HTML/JS/CSS/icons)
// using stale-while-revalidate, so the app opens instantly even with
// no signal. Never intercepts /api/* requests - those are already
// handled by the app's own IndexedDB queue/cache in offline.js, and
// double-caching them here would just cause confusing stale-data bugs.

const CACHE_NAME = "harambee-shell-v1";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  if (url.pathname.startsWith("/api/")) return; // never cache API calls
  if (event.request.method !== "GET") return;
  if (url.origin !== self.location.origin) return; // same-origin shell assets only

  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      const cached = await cache.match(event.request);
      const networkFetch = fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) cache.put(event.request, response.clone());
          return response;
        })
        .catch(() => cached);
      return cached || networkFetch;
    })
  );
});
