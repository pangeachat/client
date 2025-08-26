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
"main.dart.js_204.part.js": "dade2360383ce51e542a052e404e740f",
"main.dart.js_207.part.js": "3b9d318945b001ac4f47b33aaaca93d2",
"main.dart.js_242.part.js": "2be2bad3e31a521ea0b88ab0da3e5022",
"main.dart.js_216.part.js": "d564afd0adfada53c8578e1a32b6d5a5",
"main.dart.js_183.part.js": "137f23b2f54dff1ff9921677ce239316",
"main.dart.js_190.part.js": "da71fb066d2f7fcefe90a583c6f71882",
"main.dart.js_193.part.js": "8dc6f986ba514528d6bd99b004ea6752",
"main.dart.js_241.part.js": "cbd19ce3c9e59844807afc4d7ae1278c",
"main.dart.js_155.part.js": "92e6a2c449155afefa74b5306c451d20",
"main.dart.js_223.part.js": "e634432420e2bfc262def2ac0d36f94f",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_191.part.js": "594304d6505a68ae5125255fcbec3384",
"main.dart.js_18.part.js": "a5ebe4b0365a4d4198b2e96bdd15c6ed",
"main.dart.js_166.part.js": "a33894e0b2b2bfe16f3e1db64c03f097",
"flutter_bootstrap.js": "98021d92d3ff5b849e20e4be867be1c5",
"main.dart.js_175.part.js": "1a77c008e681df3938ff8ebb3d357719",
"main.dart.js_205.part.js": "7103e5d6267c85bef2584a07628b3684",
"main.dart.js_211.part.js": "38031f2af128686e074233f9a9c2559a",
"main.dart.js_254.part.js": "2546601e6e6fd110865d7967932ddbb5",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_252.part.js": "420622767dcb3f6e23ecafe23ac2f656",
"main.dart.js_240.part.js": "a1cd7aca11d20c1b733d9f9e5c707608",
"main.dart.js_167.part.js": "2c053028c4a22f7f6eb432fcdd04c13d",
"main.dart.js_237.part.js": "1a7605019618f8fdb3955295041cd7e3",
"main.dart.js_225.part.js": "54f0f34c5281f8fc2d01a2229c63a848",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_168.part.js": "0a0e84f234f460101c363b44d52a9ad8",
"main.dart.js_236.part.js": "48349a4a68ab8ed11009c516e0d1864a",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_202.part.js": "b725a7b1c31bcc26a90d4e0f18404ce2",
"main.dart.js_229.part.js": "d6fd4b16c0cfafe8699d74fffed0bf86",
"main.dart.js_234.part.js": "6c447cef94d0cd32732888443364dc2b",
"main.dart.js_231.part.js": "e3ca2ea38ec2d8d7324967b3a6877f77",
"main.dart.js_206.part.js": "c1ebf3cbf45ad6ff459f0df77efc8d90",
"main.dart.js_217.part.js": "9dadb6b0daf20a5669497bdf23924329",
"main.dart.js_243.part.js": "ad5ee55aa9c370bb9828dde2bc417d2f",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_247.part.js": "d744e1936985d10625a81edbebc3dbc2",
"main.dart.js_200.part.js": "5cd6706b1a2f1bb78d555d8015a57797",
"main.dart.js_235.part.js": "ebd63fad9799dcf280de691f46e46664",
"main.dart.js_258.part.js": "7f634620ee19f24cc5ffc5b6d6472acc",
"main.dart.js_210.part.js": "a068d103edb2a41f3fc202578b9f8c2e",
"main.dart.js_256.part.js": "eef0311e54241e465ad66dbd98cd3755",
"main.dart.js_249.part.js": "f170873960b50b36109c36b48648f6b3",
"main.dart.js_251.part.js": "703850924f688a67c84a45a3178b1c4b",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"main.dart.js_257.part.js": "9f12413b453d6ddde06077bbf6f6588c",
"main.dart.js_1.part.js": "ed422ffca4bf383562d9a10835e3f179",
"main.dart.js_215.part.js": "3f2c3de4dddce44c6986d5d58da8a8b1",
"main.dart.js_189.part.js": "d83ad194de1dfd6cca8dd28c99605f46",
"main.dart.js_255.part.js": "abb4c5068b5255d973863fd6965476b1",
"main.dart.js": "a60fda71a2d773fb39990d6e505723fe",
"main.dart.js_253.part.js": "f062c2920ad465b62df32ad88c16c833",
"main.dart.js_181.part.js": "33710769d5be96be7ddd941242c2bd55",
"main.dart.js_233.part.js": "f33edee9e6bbd66580f86fc65d828c56",
"main.dart.js_248.part.js": "67388ddf4226601b433c842315d50cdb",
"main.dart.js_222.part.js": "cf3ddec1d54af1f428870cc04a36c334",
"main.dart.js_157.part.js": "c1b86989322ebb2aeded246ce7bbdc46",
"index.html": "8853300df32d44a5b89c8d93bb664a0f",
"/": "8853300df32d44a5b89c8d93bb664a0f",
"main.dart.js_238.part.js": "3ffde8b3b7bbb8edb42e59c39a8d1538",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "d576b4ab8e8e9707baf8d411c260499a",
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
"assets/fonts/MaterialIcons-Regular.otf": "9ae700bcab5eb6e1dcfe18d97df3905d",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "fe69981ba27be94ea5293695c65fc9bb",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "f1799fd885fb69d74b633431e65c87ec",
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
