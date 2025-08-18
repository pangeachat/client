'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"main.dart.js_204.part.js": "a37666fe6a06135c71b9683d7ae8dfd9",
"main.dart.js_207.part.js": "7245d9d8116f3b08f3150d46d403b3d8",
"main.dart.js_242.part.js": "eaf31646584aed907cd791fa70de121c",
"main.dart.js_183.part.js": "08717923e5d29cca7834326d9ffa271a",
"main.dart.js_239.part.js": "7981c3b9a79190f645771432daa37173",
"main.dart.js_193.part.js": "9ab9bbeec388f3b8f340d82cfd914aba",
"main.dart.js_212.part.js": "e2df26f5a7b3ee4156ff90b824490e6a",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_191.part.js": "bcb70d417e03adf259de4c567dd04944",
"main.dart.js_18.part.js": "f22b79ae9dd7ee1e101fa35167599dff",
"flutter_bootstrap.js": "ad2b05ed79da2bdb8782b1c93d7fd312",
"main.dart.js_227.part.js": "152a4a219fe9325fffc3b23c14809660",
"main.dart.js_192.part.js": "03bee90254aea5172a8d7bcba6c89c80",
"main.dart.js_213.part.js": "2cb48091c42fb26259faef7f20e3d29b",
"main.dart.js_254.part.js": "acd8193d570517ac23b553e174275639",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_169.part.js": "860ceaefefc3a80696fcfd9bca23322c",
"main.dart.js_240.part.js": "0e9a719127dd47aa71dae5877d9aad71",
"main.dart.js_209.part.js": "ab3e8cb0c45a35e549a5ff454f7ef8d6",
"main.dart.js_218.part.js": "cdead5cb46a8ce58815d8936862eb50e",
"main.dart.js_208.part.js": "7d203c3d7ebfd48c0107379d34a48ca5",
"main.dart.js_237.part.js": "d32199ed480de17fcfaca1b82047a9f9",
"main.dart.js_244.part.js": "f87baf3b21f5f0595efc4b70634b0c65",
"main.dart.js_225.part.js": "8f17b94bf8bcb5120f7d395e1e0f7dfa",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_168.part.js": "b0e80c7628c4902bdc517e98bc31b405",
"main.dart.js_260.part.js": "51299362e164a98cf7773ed11f17153c",
"main.dart.js_236.part.js": "1c546cb63a9a9d59bd2efc4bb893e836",
"main.dart.js_224.part.js": "87deffba628715f689c62d9d7fbd1088",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_202.part.js": "791fde0949d32e3f83520f82c419d5ca",
"main.dart.js_259.part.js": "d9904dd58e62d1d6ef18b0a7b95524b8",
"main.dart.js_231.part.js": "a20a42c38291c31163dddaba383c300f",
"main.dart.js_206.part.js": "86050bc3d6597946be5cd78d0193eec9",
"main.dart.js_217.part.js": "e97935c74c7de51e3e218b0775a99233",
"main.dart.js_243.part.js": "4e7e162b3508c45d892e8ddb55e9d06c",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_185.part.js": "12909d94ca6dd746e3553f9b1f17e94c",
"main.dart.js_235.part.js": "6909feed0ff14cc05314fa0d9fd995ab",
"main.dart.js_258.part.js": "fb1c1ad3bcc26690d8e8319338baf4a7",
"main.dart.js_170.part.js": "d84b8edb608852412acf901e9b297289",
"main.dart.js_256.part.js": "0baee49ff90d1f623ae281a57c5c0cc0",
"main.dart.js_249.part.js": "db7ba8710c8ad526c6f216e3c536f247",
"main.dart.js_251.part.js": "608cb74ac8025599e1cd3a392894ec8a",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"main.dart.js_257.part.js": "adea6bab1b14f3ec8b059168d926a2bd",
"main.dart.js_219.part.js": "893302ed9eb0e5c9d91ff13e3aff3491",
"main.dart.js_1.part.js": "d85bd147a37025e8d8b1aa83ea3faee8",
"main.dart.js_177.part.js": "5c8cf0f91f68fc215724cd2ce3791083",
"main.dart.js_159.part.js": "897b7b5b833067ca88c3bf3293b0ee8c",
"main.dart.js_255.part.js": "37a73bd96261e7b96e2f3c84a2f26bb0",
"main.dart.js_250.part.js": "f38da8dc562b56376b295a8ee4ab8719",
"main.dart.js": "689299959caa6e2ef386155395362c26",
"main.dart.js_253.part.js": "9399d51a5a7a9257f90950f4bdacf8b6",
"main.dart.js_245.part.js": "28aa5f542c895831c3c04de72482cb20",
"main.dart.js_195.part.js": "76aab5fe4d19e0660eac04a4090c5c92",
"main.dart.js_233.part.js": "443be9f47535fddfaebc8cdb5091f6e5",
"main.dart.js_157.part.js": "a926497f4b91a30036f857b5adf0e0f6",
"index.html": "2e9e2c9b568f4092f14171d9bb3898da",
"/": "2e9e2c9b568f4092f14171d9bb3898da",
"main.dart.js_238.part.js": "395bc7a358858784adcc9c4f0b330f77",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "7f759f00ff775c6dd13b26289c02d28f",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"assets/NOTICES": "1e397ff2aaad1a91003e6288334bbba8",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
"assets/AssetManifest.bin": "2d9c9db994bfcebec6a125ba8d0fac63",
"assets/AssetManifest.bin.json": "1f4b9d7a9add599ed8d44f4e11c151b7",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/fonts/MaterialIcons-Regular.otf": "020cb22bfbe514e493c6a21db09e7782",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "27bc78686e8001cd1c74aa5ddb3aefe3",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "1f1f9457405b0a2be70540f6a1a4596c",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83"};
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
