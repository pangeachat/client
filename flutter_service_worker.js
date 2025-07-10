'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_228.part.js": "295bd217213ed04a0b2949e4c7d9b8b2",
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
"main.dart.js_242.part.js": "76531817be78d4c53c9503dc54ff2749",
"main.dart.js_243.part.js": "df626c216ef17cb1e26d5b3171612ba7",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_217.part.js": "2d66bffca05a774e3e5282710377a309",
"main.dart.js_231.part.js": "fec566796fd9aafce98d5410c05cea7f",
"main.dart.js_163.part.js": "79fd56485b5013ebd49486c18c8b78c5",
"main.dart.js_259.part.js": "502485624f591b7c42a41358563bbe94",
"main.dart.js_262.part.js": "4d40557d2cff42de302e3fb9edab5ce1",
"main.dart.js_187.part.js": "6e644880e2e94f24e37498eb57e482b3",
"main.dart.js_223.part.js": "af7b50c8e2b7f6555beefe8d0a30acbc",
"main.dart.js_172.part.js": "d5504bf267ae34dc2e41883740b79027",
"main.dart.js_254.part.js": "0feb3ba8d363b5a739bf3b20fc2e10f7",
"main.dart.js_19.part.js": "a41328dad5767dad476e32056d83171c",
"main.dart.js_199.part.js": "3c428ce9993e60780c127f9c028dc40f",
"main.dart.js_248.part.js": "3928e50bfa0c4631d9f96408cc341d9a",
"main.dart.js_263.part.js": "8b85f21d6bd886b3540a8ec070245514",
"main.dart.js_241.part.js": "da942c66f4c7c6d5041b425b3ba9ea19",
"main.dart.js_249.part.js": "2afdeb324ed096d514d60c36e951491e",
"main.dart.js": "fe1d119defb06de2dc8f083c0ade8775",
"main.dart.js_253.part.js": "cd003447cd3aec3d0cfb85159af03065",
"main.dart.js_258.part.js": "2fed02b8ad581ffab462b6abe27963f0",
"main.dart.js_260.part.js": "ece70aad0106aae30cb56943953a7ca3",
"main.dart.js_216.part.js": "a892c2614718cd613cd4114a0e0afb9e",
"main.dart.js_1.part.js": "06e872681134fb9158f8ceb880eedf2a",
"main.dart.js_195.part.js": "9cc36882139487afd5396e53aa8776a3",
"main.dart.js_196.part.js": "df7b16f97004e1c0c5d2926c5eb7ce2c",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_264.part.js": "f6613c3472b178e65582e3f37244932e",
"main.dart.js_213.part.js": "1ce0d9ba3b1ea99a9815d3d85a385751",
"main.dart.js_222.part.js": "ac2a307ac17da1240cdeccbb6952be9b",
"main.dart.js_239.part.js": "c7052465730beac4f5cfa6784453a9fe",
"main.dart.js_240.part.js": "67b140b347aa82b5eb59c9a4fbec4cae",
"index.html": "f036c600f807189b7705843545eae107",
"/": "f036c600f807189b7705843545eae107",
"main.dart.js_181.part.js": "83123f78d1cad7cf107b1b164dd941ae",
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
"assets/NOTICES": "fd02da22ed3c09bc44f112284e05aba0",
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
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "67b6a8e018c98ec8255176e9928ed864",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "4e7d891437b42b8fb35448f1f4276535",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
"assets/fonts/MaterialIcons-Regular.otf": "93d4a86ed43a6a5bead6e5125c55ac94",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"main.dart.js_197.part.js": "63905d27a090853c7e8c761fca78e988",
"main.dart.js_211.part.js": "d2e8ebd8d73ab996523218d33ca735fe",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_189.part.js": "b887d4926f90139ad371381f4adc34b8",
"main.dart.js_161.part.js": "bc72fa6fd9a05097dd3cea9805cd2809",
"main.dart.js_229.part.js": "5f5bfa06df76530f8451ebe60b973ce8",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_246.part.js": "5ee3731990d711fe5d6e855cacbe423f",
"main.dart.js_173.part.js": "3f37503b08dfc1daa6b7f47dc695b1f7",
"main.dart.js_244.part.js": "e3f1c62c65b4a2b785b18bc0376950df",
"main.dart.js_261.part.js": "494566e75b414ff87386e075d3412ee3",
"main.dart.js_208.part.js": "517ab26ed37266064e7fe1e7823b5de7",
"main.dart.js_255.part.js": "733a115f55ecb4b34b7193c17dd6a3fc",
"flutter_bootstrap.js": "ec8c5b472a9a8ae17163eb0efda9d489",
"main.dart.js_210.part.js": "f38ac3e864516bcba2d423e1d0eda27a",
"main.dart.js_174.part.js": "5b48005c2e4d023659d11bea0ff241eb",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_212.part.js": "6e516edca057ed35bb6d12859f2ab0c6",
"main.dart.js_221.part.js": "970bbd5504b2541621a8a79157a323a1",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_247.part.js": "2f9d55bb6e218fc47789d05bf1e6c059",
"main.dart.js_237.part.js": "c0676976b810040165696112882998de",
"main.dart.js_257.part.js": "d4dcd2feafcc5cc970176281710697cc",
"main.dart.js_206.part.js": "9fe260567900fd8e0cdd606ee4bd7397",
"main.dart.js_235.part.js": "ca1bcf88c13942c6e4c1597d101799ea"};
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
