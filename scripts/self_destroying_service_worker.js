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
// document mid-activation aborts the activation and wedges the worker in
// "installing" (the bug the first version of this file hit). Reloads are
// page-driven instead — via the postMessage below and the eviction script in
// index.html.

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const cacheKeys = await caches.keys();
      await Promise.all(cacheKeys.map((key) => caches.delete(key)));
      try {
        await self.registration.unregister();
      } catch (e) {
        /* best effort */
      }
      await self.clients.claim();
      const windowClients = await self.clients.matchAll({ type: 'window' });
      for (const client of windowClients) {
        client.postMessage({ type: 'SW_SELF_DESTRUCT_RELOAD' });
      }
    })(),
  );
});
