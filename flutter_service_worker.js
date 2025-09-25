'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_207.part.js": "022e068bb7b1c6033fe740fe7520dc39",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_243.part.js": "f32004b7a7c22a508cd32e38dca4561c",
"main.dart.js_1.part.js": "b68fb232f184b2a3c4ae305cfc3ec0c4",
"main.dart.js_260.part.js": "4250da3741086555154ce7e9be7f8d8a",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_173.part.js": "6d778fae5cb22e07194c406434d9fe94",
"main.dart.js_162.part.js": "e10cb92ed5839d2f51408d8b4ca55397",
"main.dart.js_245.part.js": "edadcaebb0596f8be539c1015b54c1ae",
"main.dart.js_250.part.js": "1d8145a87bdce468afe0f6a054dfaae1",
"main.dart.js_214.part.js": "b9963b64b67444c6c5a2159ddb1ccaf2",
"main.dart.js_266.part.js": "dd30524e7b2d67857a41bb6fe6cd93eb",
"main.dart.js_246.part.js": "6f793750594b59ca251b0451b59b631e",
"index.html": "d7e6288ab091dc6995542c3632ddde30",
"/": "d7e6288ab091dc6995542c3632ddde30",
"main.dart.js_251.part.js": "1c350be4c8af1b2876011e2302d729e9",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_258.part.js": "58845e207b421b9fb39d883cf362e601",
"main.dart.js_244.part.js": "b8055c4e06e0f24db6a62712dc37ec5f",
"main.dart.js_242.part.js": "35ad63d75316d742014cf49e29f49989",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"main.dart.js_265.part.js": "1ec019fbc2ffebdd751453401405f501",
"main.dart.js_261.part.js": "ee5361e71012bc6b13f119ecb45a85c3",
"main.dart.js_262.part.js": "3603a9e0d7aec4d265a9b94367e13e56",
"main.dart.js_263.part.js": "f94a5cfdbbbcb6a5985dd59041580784",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "faf27bc559f85826a2bcf26f9879abe3",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "d2ad81798d30a17607f7caf65c30b790",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "2f8496558e2fc1c9a376747dcc6fc39b",
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
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/check.svg": "e5130caf87a0a37b98ea74e80b055ffe",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/fonts/MaterialIcons-Regular.otf": "418336e0d93d9a0a52a6369576646804",
"assets/NOTICES": "9f24b4d987496c2cc817fa20aa20cc78",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "74e8a80a1b0f561fa1c2cb4cab72d1e3",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"assets/AssetManifest.bin": "a9660d84aafbdaa38c1997e07b916f48",
"assets/AssetManifest.json": "ca0ab9c3bad77ab855faabdff0ce459d",
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
"main.dart.js_210.part.js": "403d4da53d5e73c341384c35746e5530",
"main.dart.js_240.part.js": "afeb5275eaa04d68b553edbc2390e6b7",
"main.dart.js_160.part.js": "8da0d5be66af7e800aa95000d022fecd",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_195.part.js": "d4ff96edb7c97dfe2495f309dcea4551",
"main.dart.js_247.part.js": "1c735ff5b09a607905749fe44deb449c",
"main.dart.js_188.part.js": "0282a12a7614f4c91aad60fcce18abec",
"main.dart.js_198.part.js": "959837dcf2f07c93f2119e89a3ee3836",
"main.dart.js_196.part.js": "28fc8abed15c229cab9175d411d0b498",
"main.dart.js_252.part.js": "2c3f284e5cc69a9e1415018ecdc61112",
"main.dart.js_257.part.js": "b8ba6fd96b8d06f619f30be69f0ca0a6",
"main.dart.js_212.part.js": "332338149f976bf11f55753e345abc4c",
"main.dart.js_213.part.js": "8068e1c93943089c24758e40408b711d",
"main.dart.js_249.part.js": "1eeee347c0e61350461188510b20f0d8",
"main.dart.js_267.part.js": "d8f0474856f74444d3e52cef0e286b69",
"main.dart.js_194.part.js": "4009c60f971bed4160f7d0a701eff3cf",
"main.dart.js_186.part.js": "c694ac528fed1707c22278b6cba41544",
"main.dart.js_22.part.js": "b4b157e2f98d706880ff816289720370",
"main.dart.js_172.part.js": "2b71443b865163f0584d4cb5017b1c23",
"main.dart.js_215.part.js": "818c24435660793b2698cd9626d7b25d",
"main.dart.js_171.part.js": "287119b81580c50cc6176c232491a85f",
"main.dart.js_218.part.js": "d90be17af0bd0d2f00347edee264fadc",
"main.dart.js_230.part.js": "254ea9e074419e8f2b0dc9f21a44b453",
"main.dart.js_231.part.js": "b064cb6a593ae7e8503189b9cd1f06bd",
"main.dart.js_219.part.js": "481a03d654f973dc1566f8c842b470e3",
"flutter_bootstrap.js": "7ab363ae288600e392493edad9929ddc",
"main.dart.js_264.part.js": "1d1fc27dcb0f07d05e228002b851d8ea",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_225.part.js": "adea8120b3ead2651f0e9d095477b998",
"main.dart.js_238.part.js": "12bec049f1a39c30a8f40398cbdacf64",
"main.dart.js_256.part.js": "68702436846ee98c88a009ff6e466c8c",
"main.dart.js_233.part.js": "ee270a7ad9a8c800a15053c617ddd080",
"main.dart.js": "88f45a3a85ce9ad62e532c090a342c5e",
"main.dart.js_224.part.js": "15d134bf69408ba57753eeeb3f06b86a",
"main.dart.js_223.part.js": "d3f2f110c0218928c22f056230f71db7",
"main.dart.js_180.part.js": "b9b57063023fee053acf44b25c58d3ea"};
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
