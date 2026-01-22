'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_751.part.js": "bedeeea9d604602763ff0fd277c387b3",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_387.part.js": "21d92a51bdb6162d83a1ebef4cbe131c",
"main.dart.js_1.part.js": "b0f196a19e559fbacde6f423f7810549",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_764.part.js": "da1a22129f59671628aa50d0f7c3c538",
"main.dart.js_766.part.js": "b4c43a619273ac0ff20440a7fe507bf1",
"main.dart.js_602.part.js": "09d761f25ab4aa37dd25ff25dec8c8b2",
"main.dart.js_747.part.js": "2a65e934ffb03d7e15a30f7dba6bcd7b",
"main.dart.js_634.part.js": "5aba14ef0368e79ea2b2c3578397d193",
"main.dart.js_140.part.js": "14b7fa1ad6464623491ddfbafdb1d337",
"main.dart.js_760.part.js": "c83c3b6441365d403ec545c9ad54f3e9",
"main.dart.js_507.part.js": "85870730c49a5dd9010a467fff5229a6",
"main.dart.js_633.part.js": "46d683d0ba2525a63f20f8cadff86b18",
"main.dart.js_761.part.js": "d8c16a3e282382aa04f882ac8613a027",
"index.html": "8067976ad213004f07094eb7695b6b9e",
"/": "8067976ad213004f07094eb7695b6b9e",
"main.dart.js_583.part.js": "ee7ab3837c7e62e69cb0055dce4abec2",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_416.part.js": "3353f89621d21dea749d225158237b56",
"main.dart.js_756.part.js": "1e42ebe8f496f68ef9f46bfda77ea0d5",
"main.dart.js_242.part.js": "33cb318795d0dd8c018338d5400c8c78",
"main.dart.js_713.part.js": "90902d48a159d98ec1e49bc62996a79d",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"main.dart.js_472.part.js": "f133dfdcff280b24b9dd8a2e7f28c6ac",
"main.dart.js_709.part.js": "e3144e056390a5afc7064cc9f114dad9",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "87ac8e0453d4d7b653467ebc63b943e1",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "d8a180a7a69f7559dc198660737f1132",
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
"main.dart.js_667.part.js": "7e580b35fc8782837a602d15c2883622",
"main.dart.js_635.part.js": "63cd7f0cdfc3fe5b903d4daa6a16c84c",
"main.dart.js_595.part.js": "13c92422c29f23e9cd5c2c5ae580f528",
"main.dart.js_733.part.js": "15e66a86788a8d45401d0c2c3d2575b6",
"main.dart.js_164.part.js": "7af2eafd406bb25f5c6d0ddab0cd7d4e",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_415.part.js": "ac5e3c056dd9e492a5aaefb53c39966b",
"main.dart.js_759.part.js": "9d5a8c4aee1f3130ddf9bcb4e01d70c9",
"main.dart.js_762.part.js": "61f13749c854adc6f57e8bd08cdcc429",
"main.dart.js_714.part.js": "1a5ead16afaef1e01bff5345b09e056e",
"main.dart.js_723.part.js": "3345a87a5cef08fcdfaab4c453f49888",
"main.dart.js_144.part.js": "d1260b3fcf2fef2a024d46e0d28839d7",
"main.dart.js_674.part.js": "96f085f64ade1b0338d69e509223406f",
"main.dart.js_567.part.js": "510bbac4773c71133548fe3b7d82ee6c",
"main.dart.js_765.part.js": "126fb2a45d38982478558f119ece72eb",
"main.dart.js_622.part.js": "097e240fdf7f335a84e4a9ea59131a14",
"main.dart.js_754.part.js": "ca14ccb301e840996f9fb703daf2f803",
"main.dart.js_581.part.js": "10379ab4ab7862c4f3554f7661ac8b12",
"main.dart.js_744.part.js": "44553b81ee4da6e61482cd5dfbe8bcda",
"main.dart.js_158.part.js": "544b285f6e9cb2c7ed2d631951be12cf",
"main.dart.js_617.part.js": "335b5d74ac2b41f663274e8f4b89fcab",
"main.dart.js_737.part.js": "194f1c7ace6f00c566430897275e30e1",
"main.dart.js_546.part.js": "b1cedbd1e5822c9965b0e12c81eb1fe5",
"main.dart.js_692.part.js": "9bebaf6220b032e974a20a001c112061",
"main.dart.js_25.part.js": "5223bb367e3d594f7b7313d775625d54",
"main.dart.js_307.part.js": "627118d6453008be8dab9221209850ff",
"main.dart.js_702.part.js": "1409803d186d7aa77b3091dc8015d596",
"main.dart.js_763.part.js": "31069253cf95ae670dbfd3e04b352ee2",
"flutter_bootstrap.js": "363f995ab04a45fed64e0b1d176d596e",
"main.dart.js_711.part.js": "7154ba306cebf014e4204af03eb2c500",
"main.dart.js_715.part.js": "26b3649da5b8ceaada7fb587cadd1a47",
"version.json": "10167606d5a64aa7c7158387ac282f18",
"main.dart.js": "788ecef6d4d2f5afedaad7e23aa5e8ab",
"main.dart.js_182.part.js": "f8bc8af3224f2890aff93104a061761e",
"main.dart.js_728.part.js": "d53bd2557c0d6af04871a5eb7e2429fb"};
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
