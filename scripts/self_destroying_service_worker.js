// Self-destroying service worker.
//
// Older web builds shipped Flutter's offline-first service worker, which
// precached the app shell and kept serving it across reloads. Current builds use
// --pwa-strategy=none and register no service worker, but browsers that
// registered the old one stay pinned to a stale build: the empty worker the
// build now emits only takes over once every tab of the origin closes, so a
// plain reload never evicts the old one.
//
// This script is published at /flutter_service_worker.js. Fresh visitors never
// fetch it (nothing registers a service worker). A browser that still holds an
// old registration fetches it on its next update check, installs it, and because
// it calls skipWaiting() it activates immediately, clears the stale caches,
// unregisters itself, and reloads open tabs onto the current build. Keep it
// published long term so infrequent returning users are still caught.

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const cacheKeys = await caches.keys();
      await Promise.all(cacheKeys.map((key) => caches.delete(key)));
      await self.clients.claim();
      const windowClients = await self.clients.matchAll({ type: 'window' });
      for (const client of windowClients) {
        client.navigate(client.url);
      }
      await self.registration.unregister();
    })(),
  );
});
