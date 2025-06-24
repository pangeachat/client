'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_190.part.js": "63f62bcf382512bbaaed1233750cc220",
"main.dart.js_247.part.js": "1aadf504fa3c385acc960ee8ea1211df",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_206.part.js": "ae5eba231c2e27115d7a6270a0dfff99",
"main.dart.js_249.part.js": "1dae644fa674770daa77f0ed87e1da48",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_255.part.js": "6df126e41857b9c7d069e314f7956c1f",
"main.dart.js_246.part.js": "71fb0ab90003967d8a066f990d419b17",
"main.dart.js_197.part.js": "8a6cf72ec97726a531c64d3eb873b0f8",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"main.dart.js_264.part.js": "627223d9dc40f2690d0105ba7a0cca75",
"main.dart.js_262.part.js": "c377a8ba75f4142392173c267672677d",
"main.dart.js_200.part.js": "37a8b4d309374ca174c111ad4676e9ac",
"main.dart.js_1.part.js": "097526861ab9f00815aa80bb841c8413",
"main.dart.js_243.part.js": "745f60643f318b83452808cb4c48ab07",
"main.dart.js_182.part.js": "548d0fd6a51f222e846a519942929877",
"main.dart.js_231.part.js": "e8c0c3123990992c0f3bb04d954535df",
"main.dart.js_174.part.js": "2c90529643dc3501a3191ebabf3c996c",
"main.dart.js_235.part.js": "cfb652e969130148a27a3002ecf5d659",
"main.dart.js_240.part.js": "7ce1eead00fe9c27181b356f5d95734e",
"main.dart.js_242.part.js": "748c619210f895efe070530deda9286f",
"main.dart.js_164.part.js": "ac91713f6ab19dabf55bdcf125a8b978",
"main.dart.js_241.part.js": "7afe7a61109157726156851045406756",
"main.dart.js_188.part.js": "b12c270fb724fc53398e1d5740e9dc21",
"main.dart.js_223.part.js": "cab28360b283f6fd2b6dd740e114d818",
"main.dart.js_213.part.js": "21250c640a45761c790e066d64716a66",
"main.dart.js_217.part.js": "2625db96f0ba309280b90c943e44ac7f",
"main.dart.js_248.part.js": "b6f8fc81175d25472b91d96ed51a9f1e",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "3213922bc687a7b4be73436f84ebf61c",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/AssetManifest.bin": "12dd895f5ba12cd429f55c1cbab069ec",
"assets/fonts/MaterialIcons-Regular.otf": "96df94620bfda2e7ef5cb9faf4f280a9",
"assets/fonts/Inconsolata/Inconsolata-Bold.ttf": "aa0f2ec17a4ba3e47bbc7ce533a93f50",
"assets/fonts/Inconsolata/Inconsolata-Regular.ttf": "e264f34eef25b5af18c240ecfca2d67b",
"assets/fonts/Inconsolata/Inconsolata-Light.ttf": "aff8f4d4930b9e50eae584d911c309a4",
"assets/AssetManifest.json": "3aa461c888442e3624f7f5159da65eec",
"assets/FontManifest.json": "df1162f2a0e446993d9403d9d817ed3c",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/js/package/olm.wasm": "239a014f3b39dc9cbf051c42d72353d4",
"assets/assets/js/package/olm_legacy.js": "54770eb325f042f9cfca7d7a81f79141",
"assets/assets/js/package/olm.js": "e9f296441f78d7f67c416ba8519fe7ed",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/NOTICES": "37551aed377d389117b210e4db27020a",
"assets/AssetManifest.bin.json": "86e580fac6e0e2f13d604c35b8152322",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"main.dart.js_175.part.js": "1241cca630cf973a48210087fb9311e8",
"main.dart.js_210.part.js": "b0c92ddc6cf192160a5d64097fc4637c",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_198.part.js": "3fb6144271a2f45b36ee88c6c54a6dbc",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_208.part.js": "77c9d5ccfd799a43fe3d9a392727259e",
"main.dart.js_237.part.js": "943d194233805e15dd4ee51310fb218b",
"main.dart.js_173.part.js": "5844879ecabd4e1142e68542debfaae2",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_229.part.js": "a6e82a30f590ed6a0672c42a354a1a7d",
"main.dart.js_253.part.js": "7b593de8c45bd5a660a0c47f7cfe0ab2",
"main.dart.js_244.part.js": "135264f1ddf8aa4fe0a08452a96b716e",
"main.dart.js_259.part.js": "21dd8d5dbb1b61a081f48ca3d3239209",
"main.dart.js_260.part.js": "dacbeb82b52fc09fb2c110b64ff374d8",
"index.html": "5605d67ac27b7d20aba8628f93409af9",
"/": "5605d67ac27b7d20aba8628f93409af9",
"version.json": "7d4bca1afdd41c8215170be9717da91d",
"flutter_bootstrap.js": "1c259ad8e8c0e718cf81a991ccc80292",
"main.dart.js_239.part.js": "42f4e54d590cc1dc8edc81c53a677b74",
"main.dart.js_228.part.js": "60a1b94d6cd412de2b8e06157dddba80",
"main.dart.js_258.part.js": "cdc1b70ff3522ebb8c9497225a08a6e2",
"main.dart.js_212.part.js": "59836836ce24191c50c3b9d3fbc953f0",
"main.dart.js_222.part.js": "f3c8b36423e0af2ed11e380287421fac",
"main.dart.js_221.part.js": "8057abd5e1cc21b7b2a64eaff153e0ca",
"main.dart.js_257.part.js": "ecc2e5ec81f14cc123c72065afbaf2c9",
"main.dart.js_19.part.js": "63afe74491a07b7681bf36d078924425",
"main.dart.js": "18f737c9ef93a82fe48f7767e1649c5f",
"main.dart.js_261.part.js": "d87741d3360168648749903cea5f3b08",
"main.dart.js_254.part.js": "fbb58cbe9363cd97e23b5a0336c72290",
"main.dart.js_263.part.js": "0ad4804155d47f091f5aa6d5101ee047",
"main.dart.js_196.part.js": "7ec1218de58f94493b17d66d15d1b3a5",
"main.dart.js_216.part.js": "8169d778ee740fcafbbf75bc5b7f15d9",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_211.part.js": "f865b0a9feeec8432a6d4946bb501e4d",
"main.dart.js_162.part.js": "80ceb8b66b6da753bf1f453132cc195c"};
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
