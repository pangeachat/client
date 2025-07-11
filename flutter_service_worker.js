'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_228.part.js": "22fdcc10380217379499ef87013ba203",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"main.dart.js_242.part.js": "b069c1cc89101e719e750dbd0ee4563f",
"main.dart.js_243.part.js": "e006ec5f1f15f23da0155e9e1c84bced",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_217.part.js": "a5a32c77189a86a244945737e9132869",
"main.dart.js_231.part.js": "dd3da0b3697c6d184836ea7be9ea692e",
"main.dart.js_163.part.js": "2b55de923f362707fe25a4b7528379fb",
"main.dart.js_259.part.js": "2e368ee3a647060abc3e5b5e5df3b100",
"main.dart.js_262.part.js": "260cdccedb794d69c596d0da28f0da78",
"main.dart.js_187.part.js": "0c2edcfbe49df3dcab60d47462007cc7",
"main.dart.js_223.part.js": "69543ee4cd50f13956b45c037cc4e412",
"main.dart.js_172.part.js": "d802b6090c6b1b370065d2ff212cbc63",
"main.dart.js_254.part.js": "17c7131bde6b7b017c8d24f1331f4be6",
"main.dart.js_19.part.js": "e4d09dc4ea85ee5d40d219b3f5380333",
"main.dart.js_199.part.js": "cce65e997d8e7b71ffc30a08bafa0dbc",
"main.dart.js_248.part.js": "6c12a43c27da54500e1d29f9b3fde0c0",
"main.dart.js_263.part.js": "efbc4d783ffd4cc52d25112cfbb912c3",
"main.dart.js_241.part.js": "b3ac35aac7d100248591e0f2df841af2",
"main.dart.js_249.part.js": "c927637daab6f2764c49fc5bda37c34c",
"main.dart.js": "8296da2798bc9204b132b71bdc450d5b",
"main.dart.js_253.part.js": "04e38cdcc12910ea41ed0c5ad939ffca",
"main.dart.js_258.part.js": "015cebd7e1f51d30315cf794ced646bb",
"main.dart.js_260.part.js": "031e229470524a7c381ff9c9bce0d47a",
"main.dart.js_216.part.js": "6ff4053b6bf468e8c524b6c44dba616b",
"main.dart.js_1.part.js": "d86dc515d851abda85035665ec0a2198",
"main.dart.js_195.part.js": "8fd1b4ac9dedbc7eae15053a441c5fef",
"main.dart.js_196.part.js": "f9129e3d1bb6072d32ce0ab553d4a116",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_264.part.js": "5cdeee3c1ecd2d665ecf57397d97991a",
"main.dart.js_213.part.js": "b358a61ef506971b0f2f608d72e7b25d",
"main.dart.js_222.part.js": "46a97c4dd39bfe4356f0da449805be2c",
"main.dart.js_239.part.js": "2144074bfb39de00d3ad575cea0f4202",
"main.dart.js_240.part.js": "2ca9f7d5be407b60292b920a0c23322e",
"index.html": "5c00808190a508b1834a235619b08755",
"/": "5c00808190a508b1834a235619b08755",
"main.dart.js_181.part.js": "44fd9682dd054515ecf2c0d073b564cf",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "760d8ea48ca7ad6dde562188f0bd741e",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/AssetManifest.bin.json": "1f4b9d7a9add599ed8d44f4e11c151b7",
"assets/AssetManifest.bin": "2d9c9db994bfcebec6a125ba8d0fac63",
"assets/NOTICES": "1e397ff2aaad1a91003e6288334bbba8",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "931b28f30f021d26ce6a102feb9ca4ce",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "98070f8605d59ea47e904bba0f94a744",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
"assets/fonts/MaterialIcons-Regular.otf": "93d4a86ed43a6a5bead6e5125c55ac94",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"main.dart.js_197.part.js": "1b0bb1ca476e5a6686583210b5764c27",
"main.dart.js_211.part.js": "243495bf23b6f17cc254a45d8234ece3",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_189.part.js": "fe6f93f3fea497736cb1886de5f0a3c5",
"main.dart.js_161.part.js": "693177f7459ccc6ff504ceef37ffbb00",
"main.dart.js_229.part.js": "3e7b02802267bc2ede17bee70992939b",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_246.part.js": "2e6c8cae98781906a844e7b02943ef46",
"main.dart.js_173.part.js": "4a4b98b1df2d372820e1a8dec0abdf21",
"main.dart.js_244.part.js": "a28108a8d5f7cdb45bbc9b8de8eda1cd",
"main.dart.js_261.part.js": "2699a582ed32537984c6442c32b4b4c9",
"main.dart.js_208.part.js": "0136fd9a7601209393d4605342469f4f",
"main.dart.js_255.part.js": "7f2fbfa800a53f0ee2b693b76a736314",
"flutter_bootstrap.js": "0c3351620ff48d2d37d508527e3c8d8a",
"main.dart.js_210.part.js": "35e63abf805333f13bbaf58d5f8eb37e",
"main.dart.js_174.part.js": "d6b96bdb82f383bf98efeedd72ad6160",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_212.part.js": "6442508595407f1c4ae4f41f6f4f71ae",
"main.dart.js_221.part.js": "1a516bc0c32ce75b61543ea52a8a2e05",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_247.part.js": "82d3724aa49bded1bc2ef894c5eb5d13",
"main.dart.js_237.part.js": "0739996ae4f461d04f4c8cee8caafe7d",
"main.dart.js_257.part.js": "41e825437f19bad2b6597cfb85bc8dd8",
"main.dart.js_206.part.js": "37edc454e8d5b8afd4906f4afd11bbe2",
"main.dart.js_235.part.js": "bb0feefb79a43f4bd94b62a043b50117"};
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
