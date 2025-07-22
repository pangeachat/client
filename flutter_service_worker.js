'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_223.part.js": "fd3a2382c39a823218865c64f7527ebc",
"main.dart.js_229.part.js": "efa0da52c95499bf9fb9eab256596839",
"main.dart.js_195.part.js": "c0f653fe484c790ea3f17c3a84ba2f13",
"main.dart.js_222.part.js": "9d3d3a40626f70d5c3b59529184e84f8",
"assets/AssetManifest.bin": "2d9c9db994bfcebec6a125ba8d0fac63",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "ec60c0b66f3e8f84885e5d91981d6804",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "247fe09e96a77f161802173eebe598a1",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
"assets/fonts/MaterialIcons-Regular.otf": "7db970616cd868f16216d66ad59b892f",
"assets/AssetManifest.bin.json": "1f4b9d7a9add599ed8d44f4e11c151b7",
"assets/NOTICES": "1e397ff2aaad1a91003e6288334bbba8",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "760d8ea48ca7ad6dde562188f0bd741e",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"main.dart.js_211.part.js": "8f2a5472db9af5b8f3eb310aa78fbf98",
"main.dart.js_196.part.js": "b86a7989408cebf90f35efe3a5362df4",
"main.dart.js_197.part.js": "9335ccea07ed8b98b5fc577ad6194d57",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_244.part.js": "0c160e55ef1cf8ccdca9f386c597fc92",
"main.dart.js_255.part.js": "c563a993b9090909ccd66f7e92f072c9",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_163.part.js": "c884b288a0b682e7185192a74ec93068",
"main.dart.js_228.part.js": "c52eb2c6ad929b8a1b26e28817ee66be",
"main.dart.js_181.part.js": "7d95a4c0a315ac78e4ec34f81a00149f",
"main.dart.js_241.part.js": "d645441c7564a38f7ab4fecbb9ab6245",
"main.dart.js_246.part.js": "ca2189baefc5594ba62800803e3336ee",
"main.dart.js_199.part.js": "e3c2be6d43db6698aa37524dd161919a",
"main.dart.js_189.part.js": "ee0611cfdd55243e85ae174e68f484a2",
"main.dart.js_187.part.js": "4f3c803243a0461da95fa2b7f77d5e8b",
"main.dart.js_259.part.js": "ce9ecdb3d0eb2772fdad29725655ceb8",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_254.part.js": "11ee99b71de8b1dbc0345dd61cd72ec8",
"main.dart.js_174.part.js": "33a0e6eea79948e9aa1c9eb7951c0a14",
"main.dart.js_217.part.js": "898b30ab8d53450ed4e32e8bf04820ec",
"main.dart.js_235.part.js": "80c06a81c8bc030a04fb281817d523ca",
"main.dart.js_221.part.js": "d0bc41ff6b0139a16c523a6c4f8d7a29",
"flutter_bootstrap.js": "66b134b4b943dc53aef05de55bf3d8ec",
"main.dart.js_264.part.js": "89ea156bfbc6c4ee5a7f2730534fdf6e",
"main.dart.js_213.part.js": "210f9c038ad3d55fcd2841d501535a41",
"main.dart.js_206.part.js": "eec51c9d8b645b8663e7ec46e8cf77f9",
"main.dart.js_208.part.js": "531eadc055dcdd4a93b536be3bdb30fd",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"main.dart.js_210.part.js": "c65655e6734e45081598493dcaf2772b",
"main.dart.js_173.part.js": "25abd8bd19d5b5454454a3626ca2bee1",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_161.part.js": "d7c64630ff5809b1d1cc0e4b1b1693b7",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"index.html": "511f0242e98c8b21b8f9a8d91a1c3d84",
"/": "511f0242e98c8b21b8f9a8d91a1c3d84",
"main.dart.js_243.part.js": "78d682a8b0dbdb1c2077fcc8235d5e63",
"main.dart.js_242.part.js": "2ef8e662e9e5ac58f1c1c46603035ee8",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_212.part.js": "2bae9e87952eb12052e8a37a4d506e72",
"main.dart.js_231.part.js": "db16efd7dc788434562bcb1f5dee9bdc",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_172.part.js": "ed53c6ae646e560934a476ba694cf126",
"main.dart.js_248.part.js": "98e8508364b73207ec66615c300c9eff",
"main.dart.js_249.part.js": "a4cd363d9c16733d7cf5670e43f50bc9",
"main.dart.js_263.part.js": "fcde0ce9f83a51b2ceec3938266ef8e6",
"main.dart.js_260.part.js": "f6dc7ad0b80752133c9880d01c1f4261",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_253.part.js": "7512198df63245588cea88624f1e7106",
"main.dart.js_237.part.js": "0549575593031093057c13f64a677273",
"main.dart.js_261.part.js": "aeda9a9875a10772c45475fa5ce2f302",
"main.dart.js_247.part.js": "cbda340dc93e1fd3c362533c8797e238",
"main.dart.js_239.part.js": "02e70ca67fe419bede76a8ecbcc303aa",
"main.dart.js_1.part.js": "e0f02dcd4db34822745d4cf881cbf65a",
"main.dart.js_258.part.js": "41a64f37081e0fc5412a06ba91536340",
"main.dart.js_216.part.js": "9755c308a0abb5f433fb71a6a065304e",
"main.dart.js_240.part.js": "a5312928097292bd7e0063813a559c71",
"main.dart.js_262.part.js": "df0dc7c061624b59fec23033e5f13f32",
"main.dart.js_19.part.js": "ea92e5d17d1223312af2ef69690a731e",
"main.dart.js": "89f9e9104747098e4e3e620620017c7c",
"main.dart.js_257.part.js": "7ba6fc5e86f7b3bcbfa2d78a4af251dd"};
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
