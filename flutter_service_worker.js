'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_374.part.js": "fa11360c608f133310fccfd3858a5fda",
"main.dart.js_657.part.js": "33b660ebcfb08b28711424935cb65d43",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_135.part.js": "ef2448e8914972e3cac8d3a31792389f",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_450.part.js": "f16e241edf5d5bf4a5b9e849fa526565",
"main.dart.js_551.part.js": "9c7f803f1f750744e1c3bc6b3a8d9350",
"main.dart.js_640.part.js": "08236832c8ace06ef0f6c25ff4070bdb",
"main.dart.js_535.part.js": "19600f8e82ae6721bf9e9e8649d29e59",
"main.dart.js_1.part.js": "e681cb39cf14d5f62395d8e595bbbcda",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_677.part.js": "cfbe5887385cb7a131731fca7e923fdb",
"main.dart.js_648.part.js": "995355b5c55dd873b0e5fba3478f6804",
"main.dart.js_672.part.js": "74f2ac351e0f58d88f32071867b75f8b",
"main.dart.js_530.part.js": "a035eb71d11f8334ed3458da4fa95724",
"main.dart.js_375.part.js": "8e5c4b11e3f58cc21cc54d951f430ef7",
"main.dart.js_624.part.js": "4b14d741cef88ff6567b7e4e17a65520",
"index.html": "b18f16810dcff0f4937dc63a505c01a2",
"/": "b18f16810dcff0f4937dc63a505c01a2",
"main.dart.js_561.part.js": "5821c9c7371cecc6514dcc23af4e413d",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_670.part.js": "190867ae801b9c6781d3ca32de216b80",
"main.dart.js_432.part.js": "3d89a6cabcc025264867cd77fb9c16cc",
"main.dart.js_521.part.js": "377a57f07487813555d771c1362df88a",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "50c84084a133eae450fffb8d6444bc3d",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "96b0bb5be20cd33cabf8b7e9d3cea283",
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
"main.dart.js_667.part.js": "5e9340ede07e6540682b1d40ede818fe",
"main.dart.js_548.part.js": "bd00b919b21747466453a1cc73254194",
"main.dart.js_160.part.js": "8e213c32ec1a06010cec6f20d1839e67",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_636.part.js": "eb0d6b6b1fe14b3998406716ea2b576e",
"main.dart.js_626.part.js": "15c5d13c43a78f91ea6f6d3d16df8516",
"main.dart.js_590.part.js": "1f68ddadce9b7edbfde3df4e408619e5",
"main.dart.js_674.part.js": "af19ca79be390b6f5e3eb1f0749b2a2e",
"main.dart.js_618.part.js": "8ab6f9f75d54d0d00b090934d62dc964",
"main.dart.js_508.part.js": "1ed49bf6999987c4a087378c4323df06",
"main.dart.js_596.part.js": "c34c41aa7a01e311d990da79eb3b301c",
"main.dart.js_628.part.js": "48fcc5471f54f10d72a8e6f19e2454a0",
"main.dart.js_131.part.js": "29492ab238035ae3415336b6d3bdb07e",
"main.dart.js_630.part.js": "f7206d5f8f2d90c30290d4a782c0b203",
"main.dart.js_629.part.js": "161b1333c9b4bc417525b945060a99de",
"main.dart.js_654.part.js": "59a409223a25933cb83adbb0808f0756",
"main.dart.js_645.part.js": "46d18e799c16bb148bbde2ccf03885b6",
"main.dart.js_487.part.js": "0ab5e980024d4c900b9942cd4508215b",
"main.dart.js_665.part.js": "167d283ffbd62c3ccab9a4f349f6f8ab",
"main.dart.js_147.part.js": "c81d1e864314c4e9bad5746d01d6b4e6",
"main.dart.js_25.part.js": "aae8744b465b68304a40ca05da4fe139",
"main.dart.js_275.part.js": "3c1e0607eb34d8808ceeaf3efeaf34cb",
"main.dart.js_560.part.js": "7e5b014a803395825c960cf2d2c275c7",
"main.dart.js_673.part.js": "a7b1463c00a0405ce713f3460778e6f8",
"main.dart.js_216.part.js": "019f77b67ec8811cdc2aec13399638e0",
"main.dart.js_348.part.js": "e993bd46de7c8c0e0edab35d3f9e521b",
"main.dart.js_662.part.js": "ac9560a39d8b9a6081be01fa7d19719d",
"main.dart.js_675.part.js": "cb8f9afe5f5bddcb54aa03751bb2193b",
"main.dart.js_676.part.js": "26ce25044b92e5a0bff098ac043d746b",
"main.dart.js_671.part.js": "4cb514b6164627d3872b6529fd91db4b",
"flutter_bootstrap.js": "adbf0ca180340ba7c7d3e21155835238",
"main.dart.js_143.part.js": "93e1db55c6828ab1e4d7c00c9d0bcfb0",
"main.dart.js_520.part.js": "3a991d938c86fe854c48622c0741be55",
"version.json": "34739ea80a78ca716b0f654fdb306d2a",
"main.dart.js": "5d17e1e647c71aa87aabcdd7159e059b",
"main.dart.js_609.part.js": "820af7b44af2d7a82d0542019877c6f7",
"main.dart.js_562.part.js": "5641ef5007be1b349b707d53bd843d14"};
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
