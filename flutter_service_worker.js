'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "888483df48293866f9f41d3d9274a779",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_308.part.js": "7911cd1e89d9c03b1eff485d3c09bca2",
"main.dart.js_738.part.js": "785ef562ee57d603d99c2535f59c1f7e",
"main.dart.js_712.part.js": "463ca04cd37dd358bd82907dc0c506bd",
"main.dart.js_243.part.js": "1ed1421dae948691b298928b3e81ddd5",
"main.dart.js_716.part.js": "cafefea9b026293b9aa3790077bcdd64",
"main.dart.js_1.part.js": "98cf6251a4ecf0f0213391ef6fb828e2",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_767.part.js": "a07a469c03397d8565a0d39979f90d48",
"main.dart.js_764.part.js": "fb79a120b5f4a960e6d71a8e655e5e86",
"main.dart.js_623.part.js": "22daf5549ac2e9b29f27ecc92eab5a83",
"main.dart.js_766.part.js": "ca4cad17132706dc4e60f470e19ae004",
"main.dart.js_703.part.js": "867b394c14924c2423b7fadaeab5aa53",
"main.dart.js_634.part.js": "724b2f86a7d8aba0ee7ac3ef98bf016d",
"main.dart.js_140.part.js": "cabbeadd3815dc1cb43e9f707a132c7d",
"main.dart.js_603.part.js": "9c66e977f9570929fca670e7f4f26797",
"main.dart.js_760.part.js": "77ff95c0dd9bccd2969bdce693d96ade",
"main.dart.js_761.part.js": "ba4ae129b6f166eaaa450c8d4b887f3a",
"index.html": "a2f69fe83f356e82127b7b58d6d9604b",
"/": "a2f69fe83f356e82127b7b58d6d9604b",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_416.part.js": "ae8228ca4449cef9b6ad4380ae24ed44",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"main.dart.js_693.part.js": "fcdb3a8b8d48ed7afcc6d7062912dd9a",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/style.css": "97cb984985b6585ee5cd0f43db05c834",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "265e2c4c1faa58a843a417c65f6db0b7",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "95c0b5dfea845f75b49b751b403e51c6",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "aa9c3ba23160b48d22ab7f65b11ab3bb",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/pangea/check.svg": "e5130caf87a0a37b98ea74e80b055ffe",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/fonts/MaterialIcons-Regular.otf": "20cc7acb062efb181601049d45114775",
"assets/NOTICES": "9f24b4d987496c2cc817fa20aa20cc78",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "d7d83bd9ee909f8a9b348f56ca7b68c6",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "4798b9f8e2c5c4eddb9dcf5459140218",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"assets/AssetManifest.bin": "f2a81232a8783811e0ff756fd43521de",
"assets/AssetManifest.json": "ac5e8711684d70efaa75ed0c9717a31b",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"main.dart.js_635.part.js": "2b9ebfb4c4dbd758a30427e3ed1af65e",
"main.dart.js_164.part.js": "80fcc233042be447e3dd7ce9f3a4393c",
"main.dart.js_757.part.js": "ad9fb7cbb31b7c638dc742e942f0b541",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_724.part.js": "d8c9045740d9abfc905a6c2ba6fb4c92",
"main.dart.js_636.part.js": "d72c94d6ed7d4c82264fa2a1e4e7b66c",
"main.dart.js_762.part.js": "336813d541aa64185cd1d13ae1146483",
"main.dart.js_473.part.js": "ad55f4b2401729269109305be9194502",
"main.dart.js_714.part.js": "8682ce3614bcb66ccea26af1191ad432",
"main.dart.js_144.part.js": "fa715640bae9b622e7dd042084faa633",
"main.dart.js_618.part.js": "02e3aedebb31254f78906fd6c25b5f91",
"main.dart.js_508.part.js": "220f67d483983ac091d64c9ffc789115",
"main.dart.js_752.part.js": "9da8dcb11f2f43c3a0d6b69345ba8528",
"main.dart.js_765.part.js": "33fa6dddaf8404ae5a79061da3455b61",
"main.dart.js_596.part.js": "8f4b305094156a8a99cf7a5b5030f716",
"main.dart.js_734.part.js": "4445b742d8d5a5a09f4b1f4ed5ebab8e",
"main.dart.js_547.part.js": "c995ef457a938e4327d71773965df50f",
"main.dart.js_748.part.js": "17342ee95bb081b9dae7b4093bfeac81",
"main.dart.js_755.part.js": "7548c1ca50f191fdd5bdfd1442fc5fa9",
"main.dart.js_417.part.js": "815ae1e13a079e0bf5f0f1e79a66aa65",
"main.dart.js_584.part.js": "5b52d5400f870c3657398451bc14ffd7",
"main.dart.js_158.part.js": "a8b7091b31c5f382135a4e4175a1d933",
"main.dart.js_710.part.js": "93805c1b41079b103105581070fc32c6",
"main.dart.js_183.part.js": "9578d68c297664b1948607070ac909b4",
"main.dart.js_25.part.js": "bfc5e0c3a022199bc2d851bf4b4412f2",
"main.dart.js_582.part.js": "d27bb5bdfe15289c797977fc661bb8bd",
"main.dart.js_675.part.js": "6f57ada377996fdab5ad10f1befb63f4",
"main.dart.js_763.part.js": "d6c8925625890b6dcc49d744c5e9a29f",
"main.dart.js_729.part.js": "e6516b46040e3942b170bcec3ce7d401",
"main.dart.js_388.part.js": "bed847711b15cf6f9354aceeaedf1605",
"flutter_bootstrap.js": "ff6836e123de3814f29b7731b1474091",
"main.dart.js_715.part.js": "4a4735517c73a384b4e090a49d228f55",
"version.json": "0e33d8419087795f035b918bcf15b567",
"main.dart.js_568.part.js": "90c8f65e3baca3bc04c5ed700a1ca3e5",
"main.dart.js": "8ec5f89d99d87ac208b435a2a600a125",
"main.dart.js_668.part.js": "4e5acc7c4892e966c18e24584eed608e",
"main.dart.js_745.part.js": "6dc90425c1c4266c7ce91da66f290636"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
