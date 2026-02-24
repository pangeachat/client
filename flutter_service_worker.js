'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js_812.part.js": "bbc1b81d2e43d7f79696b3a6a961dda8",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_716.part.js": "040f9ff3a995c0bcc87dc7d9d1a2b95f",
"main.dart.js_804.part.js": "269239a17f4012270cfa104c51d3254d",
"main.dart.js_792.part.js": "24f641de3f9bb24d9596ec6e77cc2f9e",
"main.dart.js_1.part.js": "9842fa24b017c9669ee8249890bff1fc",
"main.dart.js_260.part.js": "cdf351bdb515b89b3fe8ef0307c2ee9d",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_746.part.js": "38cd40de6e1b558be07b64e42beb2eab",
"main.dart.js_27.part.js": "f0c12363b53a395951d7816ac4cf8fda",
"native_executor.js": "2dc230e99daa88c6662d29d13f92e645",
"main.dart.js_627.part.js": "5a5570ac005b78c2c2ab8d506e620b9d",
"main.dart.js_610.part.js": "5e77f0913e8c2fbc2ba26dec9e766661",
"main.dart.js_760.part.js": "afdb3c6005cf1173fe3259df41e46ce9",
"main.dart.js_169.part.js": "6cff4f794b1d8ef3b4a552c841531ea0",
"main.dart.js_761.part.js": "077f3ec978629101f9b3503d7a5e705d",
"index.html": "8fbf32ae4939275883f440d96b3f0c52",
"/": "8fbf32ae4939275883f440d96b3f0c52",
"main.dart.js_613.part.js": "609939b3daa3efef312c6cedc15d261f",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_533.part.js": "e43e29a2414f834b35cbad8281ec03a1",
"main.dart.js_670.part.js": "5490781fe079cb3685cbf0ba5c82ddb6",
"main.dart.js_327.part.js": "fd3e793f5a883df06d080b577657b1e2",
"main.dart.js_2.part.js": "c8fc2852582fed4628887e0c62964ef9",
"main.dart.js_149.part.js": "fef965b706244c893c376500999ec7ea",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/style.css": "97cb984985b6585ee5cd0f43db05c834",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"main.dart.js_816.part.js": "51cab1c57480ab6a4246d235b4bfe952",
"main.dart.js_781.part.js": "94292545d2809770bf598700ac01f533",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "265e2c4c1faa58a843a417c65f6db0b7",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "1365d9453a7de3b996d2ca137ee86238",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "f86466459aa39dbd7a2d9aacc105a154",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/pangea/check.svg": "e5130caf87a0a37b98ea74e80b055ffe",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/fonts/MaterialIcons-Regular.otf": "fa03b90f8c6adde6c7a86bc05eba4b62",
"assets/NOTICES": "456b83857b32b7a3d9c3043329db5a8a",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "d7d83bd9ee909f8a9b348f56ca7b68c6",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "42d15127dcae904a257a1ca5c6778866",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"assets/AssetManifest.bin": "f2a81232a8783811e0ff756fd43521de",
"main.dart.js_771.part.js": "452b5c28b70b4469fb3e4974d852cb4c",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"main.dart.js_814.part.js": "965ecc678b8ed3bf008e37e5fd67fb17",
"main.dart.js_815.part.js": "56e16e911bfc9765695f286f20e4f674",
"main.dart.js_757.part.js": "710c668715ec3021685c1ccca5b99f3b",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_776.part.js": "314acad01b0a623df3dd923061787d2f",
"main.dart.js_759.part.js": "dddfe790c706c849db6dbb7b60b54ee5",
"main.dart.js_636.part.js": "16c09b9ebe1089f766717eab7d5879b5",
"main.dart.js_669.part.js": "2897e49b0268083e9dd9bb402aacf25c",
"main.dart.js_572.part.js": "cfced71e969d6df09806dbe29c029af1",
"main.dart.js_439.part.js": "ffc6c2beff64625b5a364fefb5dfa400",
"main.dart.js_802.part.js": "c65a5aa9fdeee5e22d0f4b396b5204da",
"main.dart.js_596.part.js": "81e51338144b4125fb1a07a750721c3e",
"main.dart.js_754.part.js": "84845f5338883fdb14228e6b2e87e209",
"main.dart.js_809.part.js": "4ca64b2f6e802d46a6ef243238c14bfc",
"main.dart.js_811.part.js": "6631815ef7897c59f20c6ebe96b26e7b",
"main.dart.js_194.part.js": "6f5d5ecc76135922d9612a49aa1c9e18",
"main.dart.js_163.part.js": "8b53ed7522cd91ff6de6eba06b17db6d",
"native_executor.js.deps": "d3b2ff826b8f04a8a253a7b1bbee99a7",
"main.dart.js_735.part.js": "c9e3d033f5081eaf487e7577184ff2f1",
"main.dart.js_807.part.js": "10928206f29e003c9a7abf0251385bd9",
"native_executor.js.map": "4081a54baff3648428eaadba1e99f99e",
"main.dart.js_497.part.js": "a50cd86b923674dfb0177ee4785f97d3",
"main.dart.js_799.part.js": "f6c1442e19e6eb3d074c6315eb70ad4a",
"main.dart.js_145.part.js": "0b3c73cc6556bb15e6d2b873d5d53b9e",
"main.dart.js_785.part.js": "865e71fa9b2daf378448e7ab060a227e",
"main.dart.js_810.part.js": "77996124072c329e30abd34cea05b7b4",
"main.dart.js_817.part.js": "4d6df7db76929de826a6f5fc5befa499",
"main.dart.js_708.part.js": "14c794da9302fb2b3015d0fc461d36e7",
"main.dart.js_671.part.js": "734a3657527cc46b92192a90a8ec28ba",
"flutter_bootstrap.js": "156bc184a2a9c382803480934e497742",
"main.dart.js_795.part.js": "603810a68fdabfc696d90c59250a1369",
"main.dart.js_410.part.js": "78aa1b3a6a72dda2d94acc9ffae394de",
"version.json": "a212cd2f9d443182258cbce594cf9e39",
"main.dart.js": "b8f13a5be259d91a7a949d2e5238ec78",
"main.dart.js_653.part.js": "f8b9be30135f0f219d153fdb59ef407f",
"native_executor.dart": "97ceec391e59b2649e3b3cfe6ae4da51",
"main.dart.js_440.part.js": "8af3785b48abe8b01f7038bb08a8bcb3",
"main.dart.js_658.part.js": "067f7452e35a89de37d70de2ca546e19"};
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
