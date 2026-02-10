'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_808.part.js": "3a756ce1484389fda8ec1ce743036ee9",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js_498.part.js": "b09256e7c006db86c1f119c78ac7ec46",
"main.dart.js_812.part.js": "6f488018b1c4c035d298f1b1cdcc43c1",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_597.part.js": "da7591a44d63faf828f31e2756a63d16",
"main.dart.js_1.part.js": "9ff53a6f23365f840f940bf985667887",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_758.part.js": "946871a98ba83626640222829fe3519d",
"main.dart.js_27.part.js": "bff9bdedfda187c5b47559b6b9bf7ccc",
"native_executor.js": "2dc230e99daa88c6662d29d13f92e645",
"main.dart.js_803.part.js": "50cef694c9c2e9da13823f72dd29b90c",
"main.dart.js_772.part.js": "acc6a1bf6f7c222d69a2473ece42f3c7",
"main.dart.js_813.part.js": "39f1000c02776a7f41eeeb36cee8446a",
"main.dart.js_747.part.js": "730d88db1178d129bb4b47e1f6416753",
"main.dart.js_672.part.js": "f370dbca0702576f6a1fa3f1cf14dc3b",
"main.dart.js_760.part.js": "ace4bb6485c482aebf095a9be75eec4b",
"main.dart.js_169.part.js": "dfe998ff105654f09286151246b052eb",
"main.dart.js_761.part.js": "c4445ac3cf00721b01ac6b9b54777a30",
"index.html": "17b5ddcb31255e71ff6a0dfb99afc502",
"/": "17b5ddcb31255e71ff6a0dfb99afc502",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_573.part.js": "9879fe3a78d330e8a137887eca366bd9",
"main.dart.js_670.part.js": "68050025310d0fa88e6fcf97e615e838",
"main.dart.js_2.part.js": "c8fc2852582fed4628887e0c62964ef9",
"main.dart.js_818.part.js": "5f5774ca16227bbf3c6421b96fbf4890",
"main.dart.js_614.part.js": "2279223a56a7591829a7657af3e91669",
"main.dart.js_717.part.js": "23152f9292c967ef7539a49855eff345",
"main.dart.js_149.part.js": "c94847817761ea93d92c3a8196706aa8",
"main.dart.js_261.part.js": "5d7a27caa194b524645bc7fd3023f405",
"main.dart.js_709.part.js": "c04762cac0312537a1c86953cde37a92",
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
"main.dart.js_816.part.js": "5ec16ee60a91ab3241c179186df3ebb5",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "265e2c4c1faa58a843a417c65f6db0b7",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "92c6a9eacd8930bf161238b323a4ab00",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "bef4a349b966011b213acd5500927e45",
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
"assets/NOTICES": "b3307bfae8490d9b21321a709892a7df",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "d7d83bd9ee909f8a9b348f56ca7b68c6",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "4798b9f8e2c5c4eddb9dcf5459140218",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"assets/AssetManifest.bin": "f2a81232a8783811e0ff756fd43521de",
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
"main.dart.js_815.part.js": "d68a327b753de2ca43d5aacfb1cb90c4",
"main.dart.js_659.part.js": "0eb5ff2c5101fce08d2f8e2c796ec380",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_195.part.js": "0892e9f01bda63c7c6f649b314393605",
"main.dart.js_762.part.js": "c890ad0acc2dab215d9a6b8a9c686fcf",
"main.dart.js_777.part.js": "cff3c420d8a687d21b6cb065354a82c4",
"main.dart.js_800.part.js": "aa9ce147f978070f3b097858e9f68763",
"main.dart.js_796.part.js": "ccb7a9b35f7baf0d92ead8d30ea1235a",
"main.dart.js_782.part.js": "266f3b560cb7ef22f42ccf3b25c00161",
"main.dart.js_736.part.js": "76ad3c077c9ef2401637588372949307",
"main.dart.js_411.part.js": "98119a6b6064a6a236a036b861e6b4b7",
"main.dart.js_628.part.js": "d90e2b470ee73e49636587313b4672c7",
"main.dart.js_805.part.js": "a24e65cddfa2b1000a5ba8df3f17c83c",
"main.dart.js_811.part.js": "057b8bfc050a8926370f3b316966c2ae",
"main.dart.js_755.part.js": "29e84b182796e5fb78df0448280e421a",
"main.dart.js_163.part.js": "63a41d9705f1767971f75415da2969a9",
"main.dart.js_654.part.js": "e391f55e6eb1482594bdf15dd6b2243a",
"native_executor.js.deps": "ed8fd28a0ffab55fcb94beb67958f24f",
"native_executor.js.map": "0f120249440b41114f93b0c72d252c97",
"main.dart.js_145.part.js": "dc37682c4dc72ab6f698d5b6a16d29e3",
"main.dart.js_810.part.js": "4dca26e9d66696808e7c8569e4e5781c",
"main.dart.js_328.part.js": "f730a4d0c5a041be1c5cac9233d20e63",
"main.dart.js_534.part.js": "1205494eeff344d0cf212289b1a8a999",
"main.dart.js_441.part.js": "312de2a518a5e0942175bf34a07a0015",
"main.dart.js_611.part.js": "87de401f5a4ea2b4e2804b1bbcb6b6a3",
"main.dart.js_817.part.js": "3916eca94388b0d9454db51aa67a6d8d",
"main.dart.js_671.part.js": "f255fcd9e1f284b2aa36d6f65683c401",
"flutter_bootstrap.js": "0f70409c4ece819ec14f0cf95b27247b",
"main.dart.js_637.part.js": "2c1c9f5aebda3c0d8375d3c55e2aac98",
"main.dart.js_793.part.js": "cbbbe725004ebbd71dc70a471e364598",
"version.json": "a212cd2f9d443182258cbce594cf9e39",
"main.dart.js_786.part.js": "42bc36ecf3fc066b412fc49f08ae9d39",
"main.dart.js": "c0ced61a3da81a25094a11ec5cb0471a",
"native_executor.dart": "97ceec391e59b2649e3b3cfe6ae4da51",
"main.dart.js_440.part.js": "826f898922399a1fa8859ff95a4fe83b"};
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
