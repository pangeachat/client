// flutter_service_worker.js — self-destroying kill-switch.
//
// Older web builds shipped Flutter's offline-first service worker, which
// precached the app shell and served it across reloads. Current builds use
// --pwa-strategy=none and register no service worker, so fresh visitors never
// fetch this file. A browser that still holds an old registration fetches it on
// its next update check: it clears the stale caches, unregisters itself, and
// asks open pages to reload onto the current build. Keep it published long term
// so infrequent returning users are still caught.
//
// Do NOT call clients.navigate() from inside activate: reloading the controlling
// document mid-activation rejects activation and wedges the worker in
// "installing" (the bug the first version of this file hit). Reloads are
// page-driven instead — via controllerchange and the postMessage below, handled
// by the eviction script in index.html. The page triggers this worker's install
// by calling registration.update() (the only lever that works in WebKit/Safari,
// where a page cannot unregister its own controller).
//
// Every activate step is individually guarded so a single rejection can never
// fail activation. A failed activate discards the worker and re-strands the user
// on the old controller — the exact failure mode we are evicting.

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        // Claim first so the controllerchange the page waits on fires even if a
        // later step throws.
        await self.clients.claim();
        try {
          const cacheKeys = await caches.keys();
          await Promise.all(cacheKeys.map((key) => caches.delete(key)));
        } catch (e) {
          /* best effort */
        }
        try {
          await self.registration.unregister();
        } catch (e) {
          /* best effort */
        }
        try {
          const windowClients = await self.clients.matchAll({ type: 'window' });
          for (const client of windowClients) {
            client.postMessage({ type: 'SW_SELF_DESTRUCT_RELOAD' });
          }
        } catch (e) {
          /* best effort */
        }
      } catch (e) {
        /* never let activate reject */
      }
    })(),
  );
});
