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
"main.dart.js_204.part.js": "1f8017d675bcdbfb2063f6c4784f371f",
"main.dart.js_207.part.js": "6138f4f38dc9eb00fce5c41ad2e7c630",
"main.dart.js_242.part.js": "e1fd4ec57122ce75e8e1fe7dd90062cb",
"main.dart.js_183.part.js": "7abe0960ff5f358dd912be242266a011",
"main.dart.js_239.part.js": "28c499894f2ad12846fa37cfa4e4c487",
"main.dart.js_193.part.js": "3a4ae7aa04de118018b2df6914cfd094",
"main.dart.js_212.part.js": "ca6f9482b0f70192b4f422d46058238a",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_191.part.js": "28c9e933d1d79ca28b1091c779f52e2a",
"main.dart.js_18.part.js": "0428d5078d9c1f8dcd1419511bec86cf",
"flutter_bootstrap.js": "5fb26f8685921a46fd750d2e6b7cf7c2",
"main.dart.js_227.part.js": "9a92c2dca8015c2bb75a134a314bebd3",
"main.dart.js_192.part.js": "4df234ef7e4c5b24cae4c6ae42030641",
"main.dart.js_213.part.js": "a94cce1175e7e20449b4484d623687e3",
"main.dart.js_254.part.js": "1ca0db8ea1c3f54afc8d72f1189a3aff",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_169.part.js": "29455d2b622a1176f535a9dc66909bb2",
"main.dart.js_240.part.js": "ca60b5cf3f77a1b8a53761e7426adf00",
"main.dart.js_209.part.js": "670f2dfd5e8ae5261bd66c30300f33d7",
"main.dart.js_218.part.js": "4f9ee11df610375aad96e659cf076092",
"main.dart.js_208.part.js": "1e047a0c6e20f6a88e22950c5e317009",
"main.dart.js_237.part.js": "1ae28260934a4825aa2849169f93c35d",
"main.dart.js_244.part.js": "fd5ef3b2cca0f6e85e148284509d3b8b",
"main.dart.js_225.part.js": "4362a792484be179ffbb1328b21106e0",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_168.part.js": "a9f4ffcd2a12764f8c791d5cde7a4f81",
"main.dart.js_260.part.js": "2dec1a1f5f4badb4b8231a2523aa1df6",
"main.dart.js_236.part.js": "8f9fb20c9199c54b1e9e84182456da19",
"main.dart.js_224.part.js": "1e91e15925e7262c2f0ea0b088585d66",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_202.part.js": "fbaebaff191bea1e9edbad44ebc6e9a7",
"main.dart.js_259.part.js": "3787c819d9b797d1ff43057899b96e12",
"main.dart.js_231.part.js": "7325fc6ed46e2fdbd200a873cda4637a",
"main.dart.js_206.part.js": "8a4519f74141c6d2c2a0e70a3432f533",
"main.dart.js_217.part.js": "0781f99c601b43125f9836dcba09576d",
"main.dart.js_243.part.js": "1295d74137044add78467ac020d1980f",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_185.part.js": "324d27c7d5e0fd14a55ee9de4b707c00",
"main.dart.js_235.part.js": "f8a0d55cc5c9d158add22c87865b3153",
"main.dart.js_258.part.js": "d248ff16fd920f009659fe7565f5ee77",
"main.dart.js_170.part.js": "ce3d6d06ba8a63afbcd401fe31493da8",
"main.dart.js_256.part.js": "2f5ce6eccddb307ab9a48180be809ade",
"main.dart.js_249.part.js": "30b4b4d0a2bd78e882761e732c5c9ecb",
"main.dart.js_251.part.js": "11fb488b2803f80e7bf624797d0cceee",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"main.dart.js_257.part.js": "cf7f96043aefa6a6fe5d231aae32ea2a",
"main.dart.js_219.part.js": "02dab65f4260feda14ab2456bb0b75d0",
"main.dart.js_1.part.js": "3b7a2b99366a633f8f250b7677e534cf",
"main.dart.js_177.part.js": "f07d5856213e5eaf527b7598f9c5d7f9",
"main.dart.js_159.part.js": "53c738f93f59f30a489873112300292f",
"main.dart.js_255.part.js": "e58bc0633a5dec89978553367a02ce1d",
"main.dart.js_250.part.js": "a7a845e5e3548358de6cc06f19761607",
"main.dart.js": "c1e6513559b6ca68302b09d57da3cc66",
"main.dart.js_253.part.js": "00bd2408d8b272f8698991a03a0800da",
"main.dart.js_245.part.js": "53c97013906e38ae5ab11a2b53a4b4e1",
"main.dart.js_195.part.js": "94f8728c890bb617a92842e241cfaf97",
"main.dart.js_233.part.js": "4f68fbc831f6199b263bcde5c82ee2a5",
"main.dart.js_157.part.js": "ae68f73158f6e78d92e4991fb7a0e814",
"index.html": "1051218efba93735a6712ecc4c777f77",
"/": "1051218efba93735a6712ecc4c777f77",
"main.dart.js_238.part.js": "f559668e992cde563eda08ffac4994b8",
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
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "f967c2ba261c45b3e1019d5e428add25",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "78724f82dfe1496d80036352e12679eb",
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
