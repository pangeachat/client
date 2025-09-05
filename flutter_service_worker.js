'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_257.part.js": "d691c9bfd71554de7806aabb1787a457",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"main.dart.js_233.part.js": "14ca38b6f4eb6b4d40b52b3054407896",
"main.dart.js_168.part.js": "69dd7633ef6b7de4c5db6db46c7c7774",
"main.dart.js_208.part.js": "d734e3aa639cd4e145da26956b4fb2aa",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_237.part.js": "48d69da24729e98c273f62e451a2566e",
"main.dart.js_240.part.js": "328689e51fcabe1a9a32d6a46b49376a",
"main.dart.js_231.part.js": "e69fdce616e80951c5d42eac0e9bd8e5",
"main.dart.js_202.part.js": "5ea32b2b42bc659d167f40d37cb7b593",
"main.dart.js_158.part.js": "933d744e70d835647d95ebaa566a901c",
"main.dart.js_259.part.js": "c6bc6fd48d4f3f46d699ac352420f6e3",
"main.dart.js_238.part.js": "ca1e06334d81baed205ede8d6abc604d",
"main.dart.js_212.part.js": "1ee08c66e408ea4586585262b7ec7feb",
"main.dart.js_182.part.js": "eb3d69f1136c35960a7aae37e634ecd1",
"main.dart.js_209.part.js": "246b61d1666f2862e0f052880e73b12e",
"main.dart.js_192.part.js": "854a8a23123c6a4296118652e94a30e5",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_253.part.js": "f460d5f5b9b0d8c52ce2317e982d32fb",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_254.part.js": "5b1e145cecb953214d1a1cfa5cfc071c",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js": "73d6111f2517958941a41ecf3b8d5683",
"main.dart.js_204.part.js": "2810c4da608dae09ace6b2293a2c3cd6",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_1.part.js": "27655f522c13969316cedce92712ea51",
"main.dart.js_235.part.js": "03cd6992fc5327afd484ecb9ed783c81",
"main.dart.js_249.part.js": "3bc13cd2be2984d7b0a4103fa108e0b1",
"main.dart.js_169.part.js": "b611764cda805d0c6b7f195eb9a616f8",
"main.dart.js_18.part.js": "d9792f3e503ad2aafb1355b6fe26085e",
"main.dart.js_213.part.js": "6bc36584eba4230989552a9273f2296b",
"assets/NOTICES": "1e397ff2aaad1a91003e6288334bbba8",
"assets/fonts/MaterialIcons-Regular.otf": "ed1f9936f28855192b59622a917ae33f",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "d5a92131bf674c6d69e55c863df96840",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "53f28da4762d160af77ad1bf7b29e10f",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"assets/AssetManifest.bin.json": "1f4b9d7a9add599ed8d44f4e11c151b7",
"assets/AssetManifest.bin": "2d9c9db994bfcebec6a125ba8d0fac63",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "d576b4ab8e8e9707baf8d411c260499a",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"flutter_bootstrap.js": "ca15434a45bab043216fa5ea9dd9a680",
"main.dart.js_242.part.js": "53c4bb5d515183e7e42499caa4415702",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"main.dart.js_260.part.js": "b8c3131ab49c7a60c5b1ffce502d3407",
"main.dart.js_156.part.js": "b1d18fa52df42004dcad5c8ab98a30a6",
"main.dart.js_244.part.js": "17b6443578ba8e0c8b5b1e1cbbeb87c6",
"main.dart.js_191.part.js": "c9f00d83de3d30e9ab5d8662651e0c41",
"main.dart.js_219.part.js": "056f1154fdf6aa33b4b141c8fdbf65d9",
"main.dart.js_184.part.js": "c5d3b59c599aff7bffe3aec20ea1f1d5",
"main.dart.js_217.part.js": "6568934936655f5451b9fc52db3db913",
"main.dart.js_256.part.js": "d5e87e9a74fbcf5f7deba3753db35619",
"main.dart.js_218.part.js": "d1ef19ac816078ff58eab65cab43bff6",
"main.dart.js_255.part.js": "5ca45da8a7f8507d690a29edb6268252",
"main.dart.js_250.part.js": "6a23b456e921ffc6ec07c537a91b5dbf",
"main.dart.js_239.part.js": "8cfd099886efc11198487f90b5e2f905",
"main.dart.js_176.part.js": "64f6746fb23c44d349bdfb7e82571795",
"main.dart.js_167.part.js": "cd9db8136c26fde7b3ce7baa77defc9b",
"main.dart.js_251.part.js": "a9b0827b3ea2bc469b81a17964d64ab0",
"main.dart.js_224.part.js": "4b182205eb17767f6a58965fed795ced",
"main.dart.js_236.part.js": "613cd5a7318007a554a3443735faefe4",
"main.dart.js_243.part.js": "67f220330a4b6f054474c1cc6c2581f5",
"main.dart.js_245.part.js": "33d730c46c54badb8c36c8fadc140cb4",
"main.dart.js_194.part.js": "55684f66489e272201b4e1c86b10adc6",
"main.dart.js_227.part.js": "b2fd611feff37480229c2cf5cfb4bb0b",
"main.dart.js_207.part.js": "50395afc7c275ee4c6f41b5f0305d6c1",
"main.dart.js_258.part.js": "371e1429c8f9a4e67d2c74b6f2462f35",
"main.dart.js_206.part.js": "7f633465eabe6c1b6510779eaeb04b66",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"index.html": "2a9e2e5ff309b7a6b261a3d3350aec7e",
"/": "2a9e2e5ff309b7a6b261a3d3350aec7e",
"main.dart.js_225.part.js": "84b6027e50e1b44f58187c9fa12542cf",
"main.dart.js_190.part.js": "d78dcbf9dd794b1f8830580d92f55cd3"};
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
