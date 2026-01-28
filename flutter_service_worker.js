'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "888483df48293866f9f41d3d9274a779",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_308.part.js": "bc1abd15dd417402e866f84946636212",
"main.dart.js_738.part.js": "f85be078b493d05a0d5f5ad2da7e01a1",
"main.dart.js_712.part.js": "e73aa43fa5fa96c31c56068f1851d810",
"main.dart.js_243.part.js": "789a7ac1bb40d87ee6b8465953368505",
"main.dart.js_716.part.js": "d61877906e0b07352f74eab6d6197f1d",
"main.dart.js_1.part.js": "51e326d4e5b582d578ba4803332d48a6",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_767.part.js": "eb4dc30c622d8eb1b658db35ea81bfdd",
"main.dart.js_764.part.js": "e90212ca449d678739dd6e42485ba6c5",
"main.dart.js_623.part.js": "f82b0b7e8293711e4f0b106b77442816",
"main.dart.js_766.part.js": "5bcd25680070c6f21eb3d710c2df21d1",
"main.dart.js_703.part.js": "7ea22e02aa3fcf14d90b3f5844ebc9ee",
"main.dart.js_634.part.js": "d87fc07409d7427a9d7050fc6a2d2eea",
"main.dart.js_140.part.js": "961683bf6605e4c5f95e0fa551875ae6",
"main.dart.js_603.part.js": "b237a48c246ab8c978be310c9b708b0b",
"main.dart.js_760.part.js": "179cb832c14f81cf731d17261df75302",
"main.dart.js_761.part.js": "6a980c432dc81ef1ac42d375fca37a7b",
"index.html": "843a910d309792c4b7606ab723095558",
"/": "843a910d309792c4b7606ab723095558",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_416.part.js": "77726c37f3472a2c36265f6bbbe19770",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"main.dart.js_693.part.js": "e36b665920b736af5fa87da20d59bfdc",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "4b3af69ccb2c243a67fe6884cf3463d9",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "6cf4ad3cb9e021f67d32e95dc8ca30bf",
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
"main.dart.js_635.part.js": "269f82e4acbefcfd5979b33627c21efd",
"main.dart.js_164.part.js": "4af77a8090998f92f1528ac45698ccee",
"main.dart.js_757.part.js": "023d829bba3353dde11d7cef3ae57bab",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_724.part.js": "16acdf538cd0211bf3e7a33c203027f6",
"main.dart.js_636.part.js": "b83316931429adc6bb9567b12cb6c8f8",
"main.dart.js_762.part.js": "6a46684456b9ac0c19dd766251a09e5b",
"main.dart.js_473.part.js": "e360e71063c78d77212cfc400f827f08",
"main.dart.js_714.part.js": "cd5a6706c0ac4104f8f697344a839073",
"main.dart.js_144.part.js": "f8ef0be410960b3fe6ef7b813955aac8",
"main.dart.js_618.part.js": "c323445ec33871d0b029916c18145e67",
"main.dart.js_508.part.js": "bcdb556967b889aeca3c24c4bdf11741",
"main.dart.js_752.part.js": "bbffd7788691aa5c128cf93c53cedcc1",
"main.dart.js_765.part.js": "ce21626108ad9b4f999492f63fab5fe3",
"main.dart.js_596.part.js": "d75a8800d7c77ec194a7b6ef860cf9f4",
"main.dart.js_734.part.js": "36824f54840746e141e26f56f9599c74",
"main.dart.js_547.part.js": "c9bdcf99984a100e5e799f45acf51564",
"main.dart.js_748.part.js": "3371787107cbd0f586eb405737ffabf6",
"main.dart.js_755.part.js": "aa2f3debba353050fabcb035d41e3bad",
"main.dart.js_417.part.js": "823767cee563659f0d1e3961f396823e",
"main.dart.js_584.part.js": "d86371f367a108b6093cfb093d81e7c3",
"main.dart.js_158.part.js": "a2f2b22c2e451ff10e1dc94bea28e3b5",
"main.dart.js_710.part.js": "b256a951e8b480b2562846674fb4d782",
"main.dart.js_183.part.js": "c235f240e4ad7c0702bfeba4db1cfed2",
"main.dart.js_25.part.js": "8b07aebe1276a149fde527f512041bbb",
"main.dart.js_582.part.js": "e1c3dd6c95b5f8a23900ec3bee4a8ccd",
"main.dart.js_675.part.js": "58ff91ae8e5194255381cc3aca9929e8",
"main.dart.js_763.part.js": "3b4a2095d7067dca563c7b59333044f2",
"main.dart.js_729.part.js": "b62b7fdb30933fceb1a090a03b183539",
"main.dart.js_388.part.js": "58cfa917c60fbae1d8c34104ca41f401",
"flutter_bootstrap.js": "b4bb6de7ba47b51d8de3d30f895d5dfa",
"main.dart.js_715.part.js": "2491fcf06c15b3b6a6b52d85b74bab46",
"version.json": "0e33d8419087795f035b918bcf15b567",
"main.dart.js_568.part.js": "45b8cd07452db964a90e94ab5fcf5c00",
"main.dart.js": "461bdb8b19cf0d06bdd5765fb5ba5947",
"main.dart.js_668.part.js": "1d81f10810fcefc52d4fd326b9274c4a",
"main.dart.js_745.part.js": "1ebb1895d0d739959d266bd8ac3de191"};
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
