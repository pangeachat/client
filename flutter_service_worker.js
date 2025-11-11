'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_374.part.js": "c4e900ab10d9388d1adf875871cbdc53",
"main.dart.js_657.part.js": "afd7418817125e02490517e261d58947",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_135.part.js": "49bd31d5dda85dfac98dcab486534006",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_450.part.js": "9687a1b964bbf1ffa90b88100e624dc0",
"main.dart.js_551.part.js": "b7701ff4d666bafdf992a04d3b615682",
"main.dart.js_640.part.js": "207a6a771b50b50ad24f713bd43c9132",
"main.dart.js_535.part.js": "8379ae0d124a2cc9a34476527fcc39d5",
"main.dart.js_1.part.js": "f2bfa17bb0b490956ca0e22ade7f0fbe",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_677.part.js": "96c252ced8b3e8115e6c0650079bd3b9",
"main.dart.js_648.part.js": "c5607bb68c7906d7bba330c257058994",
"main.dart.js_672.part.js": "9ec3d2d75f41331bc560f58376814eee",
"main.dart.js_530.part.js": "6d2d318d1a27ca6ddd27d33583e9f3ee",
"main.dart.js_375.part.js": "40d6ded14fc3037e1d78e1df91b388fd",
"main.dart.js_624.part.js": "fd13d4af969fc84232cb173c5c115a5a",
"index.html": "3f6f63411d67de5698b2270e45cd3650",
"/": "3f6f63411d67de5698b2270e45cd3650",
"main.dart.js_561.part.js": "a0ed0217fe0558f7f53092b311c9b039",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_670.part.js": "33a62a7ae3ffdea795b046190437ef29",
"main.dart.js_432.part.js": "83f403f260ada716a20e84f65994fef8",
"main.dart.js_521.part.js": "20b01aa2a0251ef96f38714edafe5faa",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "2f77f71c5da8f5da6ec171ff63a38eb5",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "c3da7c850886886ab6baa11f84054026",
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
"assets/fonts/MaterialIcons-Regular.otf": "f36df5056248ace81de45db52b5f2ed2",
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
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "6e2162f9214630d3a5396f0b9a823cf1",
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
"main.dart.js_667.part.js": "2a2d6da082c6efe527cf32d2961e1e91",
"main.dart.js_548.part.js": "fdcc6db33d4c0e1585c095d3318c0e31",
"main.dart.js_160.part.js": "75be5a41bf8d2f2ea783a8e6e4afa0d1",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_636.part.js": "860b5cb3fa2389ebf1f58040e3ffb3f8",
"main.dart.js_626.part.js": "38b81f12711415f84b9b501b766963a3",
"main.dart.js_590.part.js": "11c5e83d6d597e365d13b29f50fb036e",
"main.dart.js_674.part.js": "5813cfa47e57f3ac3d037742276dfb9f",
"main.dart.js_618.part.js": "b8460e44caabb9985c571cc7971fc9ba",
"main.dart.js_508.part.js": "89c5ee4e44578e3dea46c0abfdb1c6af",
"main.dart.js_596.part.js": "70ee4ebfec55ee46f48bad79c35a7b0a",
"main.dart.js_628.part.js": "ac7a0f67ecab42cce1a0fb1f4630e6a3",
"main.dart.js_131.part.js": "2360fc478ee7dbebf83d0df52bbb4de9",
"main.dart.js_630.part.js": "a04b7e393280c12378334fe1d482e673",
"main.dart.js_629.part.js": "b6d4ecb3e63fa099b2e347676a7ce684",
"main.dart.js_654.part.js": "f84d638ed7f24099ee1412e14807ee56",
"main.dart.js_645.part.js": "f917436c90b222e887752e14e2c75343",
"main.dart.js_487.part.js": "c2732072fa2651794c8b37f21248db30",
"main.dart.js_665.part.js": "25053f6813249570d4d543e54a8e1c7a",
"main.dart.js_147.part.js": "94585103dd7ae113027782b8f6d930a9",
"main.dart.js_25.part.js": "6de0211e7bae9198081793a2b55f6857",
"main.dart.js_275.part.js": "9c7a55251fb9e92444d6b5243c043694",
"main.dart.js_560.part.js": "a27f58c1dc6f6218e91cd1e7715ebf68",
"main.dart.js_673.part.js": "4f9fb7d8a4fb150f0e999ce149540f52",
"main.dart.js_216.part.js": "178f355d3905937b804af4e9041808b3",
"main.dart.js_348.part.js": "bd893cccd4b7b213fa17dd544a409a97",
"main.dart.js_662.part.js": "697d4a8da5ae8a9c56fc8448c01c259b",
"main.dart.js_675.part.js": "17f45d6fe0a36328cdd3d8a8b5f031f0",
"main.dart.js_676.part.js": "de3467268ddfb81c6c495cc537acaf26",
"main.dart.js_671.part.js": "cc31bb661c4d982ccefcf19f99ffaad4",
"flutter_bootstrap.js": "0faafb0b7c6cc57043e28534337336ce",
"main.dart.js_143.part.js": "ce1ea4f1a9458f2ce1a75e1cf465ab3a",
"main.dart.js_520.part.js": "b66718e28d62cf815e474dcb1509dcc9",
"version.json": "34739ea80a78ca716b0f654fdb306d2a",
"main.dart.js": "2815d2db755b0ecae25501454121ebef",
"main.dart.js_609.part.js": "610532cfcfea4c7e9a06b63a1ca2b597",
"main.dart.js_562.part.js": "8da20a209e603218a8532b9133e2e090"};
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
