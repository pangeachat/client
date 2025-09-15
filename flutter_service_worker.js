'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_257.part.js": "834eb7debaadbe7abc200ad25a3ae001",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"main.dart.js_233.part.js": "bff66015f04fb808c573c88c98615b50",
"main.dart.js_168.part.js": "948c9088c0a12b827f0ae57351179ea6",
"main.dart.js_208.part.js": "8b255caab6fe6f3ddd8acbc36f34cc08",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_237.part.js": "c833550a33299e7ddaf34fc5a4f73a9d",
"main.dart.js_240.part.js": "1f6078bfdefa63b73b2cf8cb14de55e8",
"main.dart.js_231.part.js": "0eb9723207e2589e9016b81f6a71434d",
"main.dart.js_202.part.js": "09c02ece4a0c8c17c12a6dcb20343e75",
"main.dart.js_158.part.js": "9be429499aa874422993ada1c998b1d7",
"main.dart.js_259.part.js": "6ec6a3ab91c3b4ca400c4da10c3a1cfd",
"main.dart.js_238.part.js": "00b3627b1671b53538e9498fafa709c3",
"main.dart.js_212.part.js": "1cd0a5a1ff4d808a1e052deaf1311ebc",
"main.dart.js_182.part.js": "72fa9f9f95c9bb9452032d4e77718eb1",
"main.dart.js_209.part.js": "8db8ef699ba4a72eb22ee7cc267549ce",
"main.dart.js_192.part.js": "be022bcdddc4f36cd1902b5d33b4e940",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_253.part.js": "9facd14c40b17faf3a98308b6808808e",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_254.part.js": "70a1487f7cff542df9d6966047d1317d",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js": "a1fbfe395b5207edb6b922581832f846",
"main.dart.js_204.part.js": "245fd846b5ba781c21c3bacca0acc334",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_1.part.js": "2e58fb9dbe24f2b9f34468a6da236d08",
"main.dart.js_235.part.js": "4d3a50d233b6eacb015320917e97828e",
"main.dart.js_249.part.js": "06e20c21134106b1a7f2fc6c38fb2a4c",
"main.dart.js_169.part.js": "46a67de7418a76b8e7cd10cd82588e7e",
"main.dart.js_18.part.js": "08367de13af6ee0c4cb075639a52821d",
"main.dart.js_213.part.js": "ce87b5fc2b8c507c65f230934618ac71",
"assets/NOTICES": "1e397ff2aaad1a91003e6288334bbba8",
"assets/fonts/MaterialIcons-Regular.otf": "f155bc93c2c0ce4a14ebf5a47f48505d",
"assets/AssetManifest.json": "ca0ab9c3bad77ab855faabdff0ce459d",
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
"assets/assets/pangea/check.svg": "e5130caf87a0a37b98ea74e80b055ffe",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "9d32931062390997f973f23708d3c745",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "ceb3bca0adf7ada966b87aa54f8fd9d7",
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
"assets/AssetManifest.bin.json": "faf27bc559f85826a2bcf26f9879abe3",
"assets/AssetManifest.bin": "a9660d84aafbdaa38c1997e07b916f48",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "23ba8c355c6817930e8f91bf5f635ed9",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"flutter_bootstrap.js": "2e055d97a4511610011fef03cd300bc8",
"main.dart.js_242.part.js": "46679476584d56b86e6157d162ca62b5",
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
"main.dart.js_260.part.js": "f08c3064dec5c4f7dd80c6b36aa706f9",
"main.dart.js_156.part.js": "a8b97792f7d289b92be4286de824e9d9",
"main.dart.js_244.part.js": "9f98066ebc25f440e6b0de1ba9237190",
"main.dart.js_191.part.js": "2261a97384486fb80842db6672fc71bb",
"main.dart.js_219.part.js": "5b6579116abd0037a5a9e5bbce0deccb",
"main.dart.js_184.part.js": "df5761b55c5443e0b3df9590159a4c19",
"main.dart.js_217.part.js": "cb2021200267bc4183262ecaac5283d1",
"main.dart.js_256.part.js": "cc0e6bdebb2b6854c155798b91f89af9",
"main.dart.js_218.part.js": "5faf6ce316ab2f730f1358efa073e5f2",
"main.dart.js_255.part.js": "6c37a1f0f2134dea1cad397b84e20012",
"main.dart.js_250.part.js": "903e2fb68bc8e1e256fa4ad7e9832c5d",
"main.dart.js_239.part.js": "27b7add696c1d5e6b97b489a233d000b",
"main.dart.js_176.part.js": "1eadc96f7bf2501ad1b8ae7ced749251",
"main.dart.js_167.part.js": "8da05991390b573f0eb874a6869e60e5",
"main.dart.js_251.part.js": "0bb7993959f8af068e642ae17466efdb",
"main.dart.js_224.part.js": "34b0d9287712b8119e44bd08732dc769",
"main.dart.js_236.part.js": "809424974c4eb8eb92ec87da3c001824",
"main.dart.js_243.part.js": "2ebb89ffdbf1e5b4a7a9c84d8b019424",
"main.dart.js_245.part.js": "d9fd6f5b3de259feb99da4e503c23ac9",
"main.dart.js_194.part.js": "0043b1b199145c493c2b3c8c4da61959",
"main.dart.js_227.part.js": "32c645062df166d602ba870c20829f04",
"main.dart.js_207.part.js": "7f77b6edad7095ff4f59ee9614278ffb",
"main.dart.js_258.part.js": "25a524fc08607d1f49a2192a43c3857f",
"main.dart.js_206.part.js": "db1e48ee58bf7b5081dc2c99b5ff9f19",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"index.html": "7e11e5e7d1394b39863d1ef488b3f188",
"/": "7e11e5e7d1394b39863d1ef488b3f188",
"main.dart.js_225.part.js": "a1b324a2410dac007b6d7d79e8185b0e",
"main.dart.js_190.part.js": "f1690d1a94624cccf95188c342cdfae9"};
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
