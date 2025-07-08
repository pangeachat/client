'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"auth.html": "88530dca48290678d3ce28a34fc66cbd",
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
"main.dart.js_164.part.js": "77cf297164e54227c81356be7a3e7e4f",
"main.dart.js_182.part.js": "eaee721cf6d03a830519bc37a4d1ea2c",
"main.dart.js_242.part.js": "9880b49ccae179a28fb837bae75597b7",
"main.dart.js_243.part.js": "36c58938164f351077067b292f96ba2f",
"main.dart.js_175.part.js": "d8b0afe813a120b654ca9457f019f838",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_162.part.js": "3495fce3b8ac0a18f825f329b33aa77d",
"main.dart.js_218.part.js": "5dff0950fdf4fdfc892c9329e2f227fb",
"main.dart.js_217.part.js": "e078e3b8a28f45fd38fe3110848ddac6",
"main.dart.js_214.part.js": "4ef7683cbe307908e64fec7b5fa83d7b",
"main.dart.js_190.part.js": "8f506c8ef84151b69b93e9515122a1ec",
"main.dart.js_259.part.js": "bcb36fffac5530d9106f57a2c4a9c2d7",
"main.dart.js_262.part.js": "822f1a32f24a494640151ded03bfe33f",
"main.dart.js_209.part.js": "3db67ebf892f046f391891f8867190b8",
"main.dart.js_223.part.js": "14e47c1b0a05bd0587c366919e2b0803",
"main.dart.js_254.part.js": "420daf67968db66325e460d1b4758983",
"main.dart.js_19.part.js": "8996ba99c82055e2967b1e5dcdc4ed58",
"main.dart.js_248.part.js": "8fcb0e1de076bbfe00f1dd46180c9df1",
"main.dart.js_263.part.js": "9b6384dd2cb7219423cff11f20f5582b",
"main.dart.js_241.part.js": "49897c94aeb134965b0b4e65d789ee0c",
"main.dart.js_249.part.js": "36c84ca0fbcad1b441826f607954559a",
"main.dart.js": "3ecf22bde2de25bd74a6ab739b35e561",
"main.dart.js_258.part.js": "ae16978e0e6be1aa76b7303ec246cfac",
"main.dart.js_260.part.js": "54ccc72c769d6ab202c3e224eb8dabe2",
"main.dart.js_198.part.js": "fa53744b27064fc45d7e6128e03e8645",
"main.dart.js_1.part.js": "c26e571cb4fdb9dd5c3a2b71727eeca7",
"main.dart.js_196.part.js": "e99a9551ef19940a996dd7b2b1af1fc1",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_264.part.js": "71c9e849ebf0d22eb01687791c5ad1f8",
"main.dart.js_213.part.js": "4704c658318fbfcffc9c2b23d5e13d2a",
"main.dart.js_238.part.js": "88b235aeaf03f5424e9d4d21fb9bc7c2",
"main.dart.js_265.part.js": "cc4eca1c183d0b3b5369b78a8ec88b13",
"main.dart.js_222.part.js": "13dfc2138ec66b360da463a309e7cbdc",
"main.dart.js_240.part.js": "1c7e613245aff41ed4f1b9df50f57da9",
"index.html": "a2f47ee8f68ace7f5a872182d172beab",
"/": "a2f47ee8f68ace7f5a872182d172beab",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "94b659e6f057c2c97b10972ba7d04fb0",
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
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "373dcb18df10a017730eb9e9ff2d7db8",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "59a178cbd32083e091577dedcb35fb80",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
"assets/fonts/MaterialIcons-Regular.otf": "7db970616cd868f16216d66ad59b892f",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"main.dart.js_200.part.js": "bbea9972f5a5122186f1ae62da75b96c",
"main.dart.js_197.part.js": "4cacf93739b1f7b008a0ec1990445ca3",
"main.dart.js_232.part.js": "9a301a4e9595d00fba1e036fbc82e08e",
"main.dart.js_211.part.js": "a3fb66fd60f52c35206d951f6fce2d68",
"main.dart.js_230.part.js": "363f6af5b21e785adb40c2d55d3c81d2",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_245.part.js": "26a2fea14e65eb43b39560506807f1e4",
"main.dart.js_188.part.js": "c09b8aa9648234341d51e2e884618343",
"main.dart.js_229.part.js": "566d5a6c2d3bf212104f2781311be4b8",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_173.part.js": "b1e889ac6c41ffcaf7de9d8d22600e24",
"main.dart.js_244.part.js": "ab428a9d66ee0bff51fb2926d8b61e6c",
"main.dart.js_261.part.js": "a1f2e7d7efface14fbcb717057052678",
"main.dart.js_236.part.js": "a35870c39b91cd5fbaa70ad967a8c3d6",
"main.dart.js_255.part.js": "92ed998522d8efabff3962df6ed08dcf",
"flutter_bootstrap.js": "af1e87d0d1ec26b28efcec47bf326294",
"main.dart.js_174.part.js": "17025f06dcfc21f6fd96060924667116",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_207.part.js": "2709937f9b3b08b6975323b93a8746c6",
"main.dart.js_212.part.js": "8dcd87096a3099be31ecd20e3e328edc",
"main.dart.js_224.part.js": "86b5b4fba4bc281a1dce101519c75825",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_247.part.js": "77224e44829eeb1f43ed82679ea00099",
"main.dart.js_256.part.js": "149ac4acf9dbcdcb209bc5e30fc3aeb5",
"main.dart.js_250.part.js": "e320f157707d23f716404b484d58c538"};
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
