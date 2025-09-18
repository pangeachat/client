'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_210.part.js": "35d439198d0df4a23e5a2d262e1a371e",
"main.dart.js_257.part.js": "fe362405d494df930f54cc82b88889d9",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"main.dart.js_233.part.js": "2ea21fe9cef09825d8d7ae1988dca8c7",
"main.dart.js_265.part.js": "7be7d37c5e3d2bacefa740096d312fcf",
"main.dart.js_22.part.js": "937e36806c5a63bde5d90c08a6738d99",
"main.dart.js_171.part.js": "57093a6d35277a02f94c994414fae051",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_237.part.js": "6a279a1e462c67fa4e077f598e53c0a7",
"main.dart.js_263.part.js": "a8257c61ff63e9356858dc1efdfc8093",
"main.dart.js_231.part.js": "29e5f55f887ad6c960c5ac22b94db182",
"main.dart.js_259.part.js": "c41d7691ad77f38e166af82f5309f2ca",
"main.dart.js_212.part.js": "a7032190a196ed7ee59d2198cf4555f6",
"main.dart.js_162.part.js": "1c67e8f35c3e818aa16c431b080dd9b2",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_195.part.js": "bfe8fa4b0db4e6bddc32ad6c39cfbb6c",
"main.dart.js": "0c972372214ed49e3f6c6640b2ab0e42",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_246.part.js": "c1a90b2129eb7dd678cd14c8158da658",
"main.dart.js_215.part.js": "2eb708e3aee5cf47086cee035b712ff4",
"main.dart.js_1.part.js": "4c4ce8baaa3170b9160195e301ff7500",
"main.dart.js_261.part.js": "f84d642a37e86bb7ec81ccdb92ec0a24",
"main.dart.js_198.part.js": "7128b9d95c1bdb14ac5002687172af50",
"main.dart.js_249.part.js": "35e5a67ae15ea9d82f69838b87319911",
"main.dart.js_213.part.js": "6b755162303cb11e20fd0995bb70337d",
"assets/NOTICES": "b3cd1c19e45eef40c75b53f27a621c99",
"assets/fonts/MaterialIcons-Regular.otf": "8c3770e3c4aa6e2b54f26898787b93a0",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "4c4d7f2e62e4ea3dceb17c46d0cc510b",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "961efe2b77b80c5365f0f8a9516fcc22",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
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
"flutter_bootstrap.js": "9de045f11ec5f78162a1d46f31d2808a",
"main.dart.js_242.part.js": "ec77b7fe80ce5ab03fbe97cc9d9aaa67",
"main.dart.js_172.part.js": "b40f4dde99646cc9ad1ac1e841d545e2",
"main.dart.js_173.part.js": "9058e9e635304af5543fd1881727cf7c",
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
"main.dart.js_223.part.js": "fa575fa27a13420c3a14ebdb29a0180a",
"main.dart.js_260.part.js": "fc12d27dfcedd42bc4a418f943924847",
"main.dart.js_214.part.js": "9aa1d78e5be3ab7d38ae921cd6a7c165",
"main.dart.js_244.part.js": "7f7583e02a80fd6b033eaff319167c7e",
"main.dart.js_264.part.js": "bd78293384b650417a4bfdbc76d958ab",
"main.dart.js_180.part.js": "6adc41f17d93e379036019362f5e0512",
"main.dart.js_219.part.js": "c54546d76e543a919c9900671feada02",
"main.dart.js_196.part.js": "e655e79301641406aa5eb8f24e484697",
"main.dart.js_256.part.js": "736119a2c97deb6143aa60d17d07bfc2",
"main.dart.js_218.part.js": "a96adddb6b93fccbfdb9a88967f6c6d6",
"main.dart.js_255.part.js": "3e573ca5b3a044f7976be4b5ec28ae06",
"main.dart.js_186.part.js": "b4770bf9a6dbb5bfc7dd0db27a15ea79",
"main.dart.js_250.part.js": "c3d57186a43b7a5d43c06c59e854a0a4",
"main.dart.js_266.part.js": "4f2d6a698c6aa72f84d92961205f2d2b",
"main.dart.js_239.part.js": "a916f9cdb0dff59033cfc7a26ad8aba4",
"main.dart.js_241.part.js": "6f6d171c969294bac79d2f05f522369a",
"main.dart.js_251.part.js": "6049469d9a18d1770add47b13d532e9f",
"main.dart.js_224.part.js": "f4c8c53e1f2ab167ae5d44a4c5ff403b",
"main.dart.js_160.part.js": "b559c788251bf5fac1c9c4bb7c1df663",
"main.dart.js_248.part.js": "285f23d9cf6655e37a427a60df075ae0",
"main.dart.js_243.part.js": "9cb6b394044a9441bde9fa2841b42e7d",
"main.dart.js_245.part.js": "73b1cce358644adf7cbca152727a4cc7",
"main.dart.js_194.part.js": "66a6dba0c11385dc95675c7811e7330c",
"main.dart.js_188.part.js": "84bc5ffca56681c93ced8963da8c30d8",
"main.dart.js_207.part.js": "bb4e6fde2d234ee031e0bce47bdfdea0",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"index.html": "e28c0d494f72970b354d922a070d2ed9",
"/": "e28c0d494f72970b354d922a070d2ed9",
"main.dart.js_230.part.js": "87810674b772f3fc2197ac5bc0b04f3a",
"main.dart.js_225.part.js": "d74ac1e6751e0a5a0462d6362374630e",
"main.dart.js_262.part.js": "7a592251ef3700fe1d310d20db5b4dbf"};
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
