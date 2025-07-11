'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_228.part.js": "2ac8e4ddbab9af66f62ba3ba745037fb",
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
"main.dart.js_242.part.js": "e010712ae9e40fa3bc04eb15160b37ba",
"main.dart.js_243.part.js": "dc9c3f5e2973ba45dc3a494b1854878b",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_217.part.js": "8eac9169bba8757ca44d66e53c9cf56e",
"main.dart.js_231.part.js": "bac03bcb690f0681d9cc3aa4e741ef14",
"main.dart.js_163.part.js": "fa56d694d8314ff3b6f0252afbe74050",
"main.dart.js_259.part.js": "1b838bef9ec5519964f62d68b0347aae",
"main.dart.js_262.part.js": "3279368b73c1a7fa53e43ed12c7816e1",
"main.dart.js_187.part.js": "59a89c4c073c91fb4dd4e97a4328679f",
"main.dart.js_223.part.js": "742c61fe54e95283a20fe9642632c130",
"main.dart.js_172.part.js": "4d27702d1f5c629a4219efb9f68a7d5f",
"main.dart.js_254.part.js": "e35cae59ff3bf5cc81aa2efe9e5c2109",
"main.dart.js_19.part.js": "427224c0bf107c2c7d2bf2bd1c5099c7",
"main.dart.js_199.part.js": "7ea84ebc8cc972be74f11c641f47b56a",
"main.dart.js_248.part.js": "4bcf7f499b9da6b16b86e2f3e0029dc2",
"main.dart.js_263.part.js": "5a1ffe52ede9438c423d6499c9e33331",
"main.dart.js_241.part.js": "59fd283b741a60833fb6d5cb2a705d9a",
"main.dart.js_249.part.js": "0e31d06c1bdca0ed3be727c71dba7a04",
"main.dart.js": "4a4400c31ad1fbf78c2ee15226c0d1b7",
"main.dart.js_253.part.js": "8aa2b7455a3232d6117985c3ae96a772",
"main.dart.js_258.part.js": "232da195d28251e7c4e037164a886a9a",
"main.dart.js_260.part.js": "c70ed876494f45153286fdaad2b96cfd",
"main.dart.js_216.part.js": "f8b961fb7b65d8939eeed98f86877890",
"main.dart.js_1.part.js": "5c70609eab34ac42064f58d7f9046b9c",
"main.dart.js_195.part.js": "42ec7128ae0cadd27fac44eccb9ee049",
"main.dart.js_196.part.js": "66a90ec79c130a5bde38306c63c4b702",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_264.part.js": "18c05ec982c323576bee16e128478381",
"main.dart.js_213.part.js": "2261fc68e453958a42623281e9aa4724",
"main.dart.js_222.part.js": "df1d6120f278c0ba0981be965b45828e",
"main.dart.js_239.part.js": "a26e5cdde7275eba31e6eccc8a6479b5",
"main.dart.js_240.part.js": "38c2e8f0dbd15047a47e667f76517da1",
"index.html": "c5fdec13740ab88947d9075057c1bd3a",
"/": "c5fdec13740ab88947d9075057c1bd3a",
"main.dart.js_181.part.js": "ed47949f9d1d7ee8dd1582fa567265f4",
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
"main.dart.js_197.part.js": "3c0846f1bccd3b724b8d77b1a772c773",
"main.dart.js_211.part.js": "9eb41c545d00f73e2e9481523d6f62b3",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_189.part.js": "eee3c2ff173a61a94f3357dc8c193544",
"main.dart.js_161.part.js": "32277f11ecca0cdec5d0c7acee86a10d",
"main.dart.js_229.part.js": "57ac4ef8468aa955aa9d71868437d61b",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_246.part.js": "999fec17032f26e63523c2aa815032ac",
"main.dart.js_173.part.js": "a9382fabcd20a20393c0dba5768b1ceb",
"main.dart.js_244.part.js": "07fd9d0056b668dd076e676f5e3f8c25",
"main.dart.js_261.part.js": "ce571645613e35a21d1621f7c20228a3",
"main.dart.js_208.part.js": "524f20e57959e367b20b26bfc1a857fa",
"main.dart.js_255.part.js": "314245f071cbc12e9a7cd276514ce4d3",
"flutter_bootstrap.js": "99efa4f11f70edcc2be18853b7274f6e",
"main.dart.js_210.part.js": "4deac467cdd7493838828f2e664495f5",
"main.dart.js_174.part.js": "0faa6440ed813d9070905cf01e1fc501",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_212.part.js": "31573c3e8e2daca19ff2188a9c1ea873",
"main.dart.js_221.part.js": "2ef7ca33914b595067c4fedd43fa3a1a",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_247.part.js": "b1bf2f4ef99438947e5839dc6e9efbb0",
"main.dart.js_237.part.js": "d916dbcc538c29535300a55e4c25bdfa",
"main.dart.js_257.part.js": "ec6b7354fc346d7cc56c56247852008d",
"main.dart.js_206.part.js": "6ec4be41125c29ee7c5f92cba9bc2573",
"main.dart.js_235.part.js": "d7f4487e360db47fbabcd93add30d238"};
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
