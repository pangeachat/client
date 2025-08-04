'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_223.part.js": "15e1ad84db834ab48f5edeeaca0076fa",
"main.dart.js_229.part.js": "bc98f9cc48531ace62d0e0a01b0edba4",
"main.dart.js_195.part.js": "c597d8652a06713bb4bdb0c29c2b5ad0",
"main.dart.js_222.part.js": "782ae8a86b7f45d53636f9becbce0164",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "dfa36d1972d14379e667d2d976a6fcd6",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "d92e51df31903f5057bf42069a909609",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
"assets/fonts/MaterialIcons-Regular.otf": "79b7abd5a16e66810c7b9f42f8064ab9",
"assets/AssetManifest.bin.json": "1f4b9d7a9add599ed8d44f4e11c151b7",
"assets/NOTICES": "1e397ff2aaad1a91003e6288334bbba8",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "1e157f864bdf4c2578e2273ec41d7773",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"main.dart.js_211.part.js": "ef5fda869649ddfd1da54e5fe64ee160",
"main.dart.js_196.part.js": "4049b7f11a687b62a2883d4446f8c6f2",
"main.dart.js_197.part.js": "b31693600f7cc9d2e46d34cac1865d96",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_244.part.js": "bd4179748a27b4225653e415244a645c",
"main.dart.js_255.part.js": "5112696b0bc1ac1f45d0f8f7530cbf5e",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_163.part.js": "063004f6ac343f180b06328c1a911cd0",
"main.dart.js_228.part.js": "f63ba3aa4ec942805e98f657b5b0d06c",
"main.dart.js_181.part.js": "10ddf29a10cec2821db784704a5e0273",
"main.dart.js_241.part.js": "e8d2970cd1a6e45be533d2657d363b44",
"main.dart.js_246.part.js": "edd3dde7e95a09f44d72ec33d04c095b",
"main.dart.js_199.part.js": "25f38bbd34ae06c97c7308956abae85d",
"main.dart.js_189.part.js": "be9a2b3093aeff114c43925e7a6829d6",
"main.dart.js_187.part.js": "57ea5f7ba5944f661d31e007892cb93f",
"main.dart.js_259.part.js": "5de0f02d8b802c1699572418365e907f",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_254.part.js": "e6317669f21e776f677f93a4c6995298",
"main.dart.js_174.part.js": "681d55c05befe3d599c3030fd891a6bc",
"main.dart.js_217.part.js": "18c367a76f4ebe9342c04278eb2b184a",
"main.dart.js_235.part.js": "d58d10cf7afcf74ae81918224d0f49ac",
"main.dart.js_221.part.js": "86be2d79728974d24439e53355e6c46a",
"flutter_bootstrap.js": "aede4730dd7c97634461b4f90c7b138f",
"main.dart.js_264.part.js": "e21cd5333acd3fddd6c3fbd17e14fcf7",
"main.dart.js_213.part.js": "dc8009474c568d5bc9a141f0beff2ed6",
"main.dart.js_206.part.js": "6cb2863cef81218775c22a66a700738c",
"main.dart.js_208.part.js": "eb3db8ed912c532a7c2a78ac953da597",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"main.dart.js_210.part.js": "2bdd0211d2480ee6d9f981b69563b1a1",
"main.dart.js_173.part.js": "6fef4e760ebd27952e7d24733c2b826f",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_161.part.js": "e2a63ff1f2c60cc78b7269875dcc8092",
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
"index.html": "0ea37a345b275922d477c35fb5adcdf5",
"/": "0ea37a345b275922d477c35fb5adcdf5",
"main.dart.js_243.part.js": "50edbd6a3edfcce08b17db07cc2e6804",
"main.dart.js_242.part.js": "59d0fa7a347edad09870149a93faad25",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_212.part.js": "95bffda624bcad7f816539de52582943",
"main.dart.js_231.part.js": "0b04a69f8628949dc721dd2dc650d38e",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_172.part.js": "71f48d5fbefd117a4b64796b02d961d3",
"main.dart.js_248.part.js": "2ec40866e84d21646de8d6053fc99019",
"main.dart.js_249.part.js": "dbf31573b12c83d1505df4c908e72643",
"main.dart.js_263.part.js": "1300cf2ed398299e5f6e99f93b7a5bb7",
"main.dart.js_260.part.js": "75773aba959c37fb7589fd93006f0e6a",
"main.dart.js_18.part.js": "82662f5dcfbf1ffa4cd2b9fdd572352f",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_253.part.js": "e43f4589276ac822397a705642104935",
"main.dart.js_237.part.js": "27a4cd51e7db19c2abd18e221356dcd1",
"main.dart.js_261.part.js": "a0374d66321ec373190c01490757002a",
"main.dart.js_247.part.js": "13a03b86a614b4018af0cd031a0aad53",
"main.dart.js_239.part.js": "c8db4da39274561d375f14a8b4182643",
"main.dart.js_1.part.js": "c39996c5ce144fb6b6db63b6632693ae",
"main.dart.js_258.part.js": "b3a0b5db2d403ce2d39ba528e188d393",
"main.dart.js_216.part.js": "c00ea27396e849f5e58224cf37b0b04c",
"main.dart.js_240.part.js": "b16105ac843416f18b839e1f5dbeb845",
"main.dart.js_262.part.js": "13111f9a212a5815fbaaaf906dc6a55b",
"main.dart.js": "dd96b7a7c0d40a5f0a3c9f3b7cb81ccd",
"main.dart.js_257.part.js": "0a7b96467ac8013f6c0b6105db4d09ee"};
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
