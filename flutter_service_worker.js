'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_262.part.js": "6aee28b476e187905f8b24a47db4d581",
"main.dart.js_167.part.js": "e270ec4fc9b0d5e0cb517d9076466b61",
"main.dart.js_186.part.js": "7ca35114c355ffb7d65e50ab8b91a87a",
"main.dart.js_263.part.js": "d273793a10f560a43a243f513330d911",
"main.dart.js_250.part.js": "d3166ee25bb23084017824f041705e0e",
"main.dart.js_224.part.js": "4ddde9496b428c7f624d2c84dbc56bcf",
"main.dart.js_178.part.js": "be4470103717e54b628027169fc0da0a",
"main.dart.js_265.part.js": "d41d4c25b569c4085c85c9dabd41c6ae",
"main.dart.js_203.part.js": "c6fe5730f3327337234041258a3383f6",
"main.dart.js_232.part.js": "933802404b063ec0d8de6cd2af19c9e0",
"main.dart.js_243.part.js": "720bd20aeeff3a25a252ed9d50d193e8",
"main.dart.js_257.part.js": "31e458f1a279f729c9bf93364e9350e1",
"main.dart.js_226.part.js": "2f97e9487da3d231c2a97e3a54f2b336",
"main.dart.js_240.part.js": "2237aa091242e292e247cf22638eecb3",
"main.dart.js_165.part.js": "53b1a7521c721eb56115d81c05945f24",
"main.dart.js_242.part.js": "5f96ff55d0bb01a8c3f47a18f7ce9ea2",
"main.dart.js_1.part.js": "57dd153bdabbde5dcdeb991acaee7529",
"main.dart.js_251.part.js": "5d03edf697d4d1c567cc8ce148c78c77",
"main.dart.js_252.part.js": "ab4cddacc2d1581d126bda683def8867",
"main.dart.js_213.part.js": "4fcd58fce7cc90f83f2cbc754df18900",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_177.part.js": "a8b546a44d21fa7f83a0e9a54d7302c5",
"main.dart.js_220.part.js": "147a34df07872aca546cb998a5dd5ee2",
"main.dart.js_216.part.js": "48501878b4d8c9d7ba53ccf73692771f",
"assets/fonts/Inconsolata/Inconsolata-Bold.ttf": "aa0f2ec17a4ba3e47bbc7ce533a93f50",
"assets/fonts/Inconsolata/Inconsolata-Regular.ttf": "e264f34eef25b5af18c240ecfca2d67b",
"assets/fonts/Inconsolata/Inconsolata-Light.ttf": "aff8f4d4930b9e50eae584d911c309a4",
"assets/fonts/MaterialIcons-Regular.otf": "c715c32a460c8e99dfb48952215964fd",
"assets/AssetManifest.bin.json": "86e580fac6e0e2f13d604c35b8152322",
"assets/AssetManifest.bin": "12dd895f5ba12cd429f55c1cbab069ec",
"assets/AssetManifest.json": "3aa461c888442e3624f7f5159da65eec",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/js/package/olm_legacy.js": "54770eb325f042f9cfca7d7a81f79141",
"assets/assets/js/package/olm.wasm": "239a014f3b39dc9cbf051c42d72353d4",
"assets/assets/js/package/olm.js": "e9f296441f78d7f67c416ba8519fe7ed",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "ca1046efe3e79da7ad7e6eecf8ac0e1e",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "ca38edc579e6425e37e8ba245b853585",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "8fc3df68fe8446810e9b5083c6561cd6",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/FontManifest.json": "df1162f2a0e446993d9403d9d817ed3c",
"assets/NOTICES": "95a76c8958c4fc9117e42bafdd538a57",
"main.dart.js_214.part.js": "097b7735d82e4d573ee14e3af01bc541",
"main.dart.js": "6e17565289cb24aa54fcdf93446676b3",
"main.dart.js_200.part.js": "3dbd06b898f2ad7c49ce0d50d88bb3ff",
"main.dart.js_209.part.js": "ee668cb55edc5b6c770930f01b4c1ace",
"main.dart.js_225.part.js": "e5d4fc9f6949b0c4f65c89895c0d71a1",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_258.part.js": "2ec83d5768b5fdf9ad8c1253ce71f085",
"version.json": "7d4bca1afdd41c8215170be9717da91d",
"canvaskit/skwasm.js.symbols": "80806576fa1056b43dd6d0b445b4b6f7",
"canvaskit/canvaskit.js": "86e461cf471c1640fd2b461ece4589df",
"canvaskit/skwasm_st.js.symbols": "c7e7aac7cd8b612defd62b43e3050bdd",
"canvaskit/skwasm.wasm": "f0dfd99007f989368db17c9abeed5a49",
"canvaskit/canvaskit.wasm": "efeeba7dcc952dae57870d4df3111fad",
"canvaskit/skwasm_st.wasm": "56c3973560dfcbf28ce47cebe40f3206",
"canvaskit/skwasm_st.js": "d1326ceef381ad382ab492ba5d96f04d",
"canvaskit/canvaskit.js.symbols": "68eb703b9a609baef8ee0e413b442f33",
"canvaskit/skwasm.js": "f2ad9363618c5f62e813740099a80e63",
"canvaskit/chromium/canvaskit.js": "34beda9f39eb7d992d46125ca868dc61",
"canvaskit/chromium/canvaskit.wasm": "64a386c87532ae52ae041d18a32a3635",
"canvaskit/chromium/canvaskit.js.symbols": "5a23598a2a8efd18ec3b60de5d28af8f",
"main.dart.js_256.part.js": "0acd506a13e5ef2f54f39ad650b0418f",
"main.dart.js_176.part.js": "50c87f6a1b2c199371a1cbadfe44d81a",
"main.dart.js_249.part.js": "165f4a933fa4cb0c593ec2f2f51636db",
"main.dart.js_266.part.js": "4ac3c5d0738debb0ea895e65744c88ba",
"main.dart.js_2.part.js": "15eb70e690b396a5372d3ea5039262a2",
"main.dart.js_231.part.js": "901272e2a640a106ad2d4b41c1985618",
"main.dart.js_199.part.js": "fc8b829f6b9ada546108f525feddfb81",
"main.dart.js_211.part.js": "610b76d4ee08e0ff2244266c110b834b",
"flutter_bootstrap.js": "1fcedc69ca2ab7c2ef8b7218a7c0ade6",
"main.dart.js_192.part.js": "b7357e2f29e8b8b25f860c662e13193d",
"main.dart.js_247.part.js": "34e6205e7df663c80788495b7b16a74b",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"main.dart.js_234.part.js": "3c26ec5d5c6cbec41a465ebfe3c7c519",
"main.dart.js_246.part.js": "dd58a43fcf51d17a46d2484e58255c88",
"main.dart.js_215.part.js": "d833c0c32d2625c04d02eadc39482190",
"main.dart.js_201.part.js": "9b20fa1d928309a6d2e1947189f906b3",
"main.dart.js_18.part.js": "d79d56faff1110cf23e64009db058930",
"main.dart.js_260.part.js": "6c01688181b501dd00999fd05efd2bd6",
"main.dart.js_244.part.js": "0e690c4938ed3f2f322c2c5fad9280fd",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_264.part.js": "1bffbe9f08d82674df255507a88efc7f",
"index.html": "1d606d4bcfa4871331e43e0cdaec019b",
"/": "1d606d4bcfa4871331e43e0cdaec019b",
"main.dart.js_219.part.js": "9750d027421eb009c0b7274478c4939c",
"flutter.js": "76f08d47ff9f5715220992f993002504",
"main.dart.js_238.part.js": "a978529bf879b3b9bf39fd9f2147ff3b",
"main.dart.js_245.part.js": "d8140a074cb624c7f0790920a6feb86a",
"main.dart.js_261.part.js": "8a0608711c642d5d105852801d1886de",
"auth.html": "88530dca48290678d3ce28a34fc66cbd"};
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
