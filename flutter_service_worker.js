'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"native_executor.js.map": "4081a54baff3648428eaadba1e99f99e",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"splash/style.css": "97cb984985b6585ee5cd0f43db05c834",
"main.dart.js_628.part.js": "9b0d1eeabc71118146f93bf885bc36fe",
"main.dart.js_800.part.js": "76fa92ac9705183d1a3d498797421ab3",
"native_executor.js.deps": "d3b2ff826b8f04a8a253a7b1bbee99a7",
"main.dart.js_671.part.js": "23be637d2b36554452021b9f63e3d124",
"main.dart.js_1.part.js": "d1d980c6ab1870dc35093d4c52eb2bc2",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_761.part.js": "8457cb4c901a3a26627e38136db1bada",
"main.dart.js_717.part.js": "fab639c2a603811822a92f64c5cc8b4e",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "5afbff06be63fd0d3cf3fb2b7d6fe49c",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "e7654fc08c8aa19c26563b64b016e131",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/check.svg": "e5130caf87a0a37b98ea74e80b055ffe",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/NOTICES": "456b83857b32b7a3d9c3043329db5a8a",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "d7d83bd9ee909f8a9b348f56ca7b68c6",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "42d15127dcae904a257a1ca5c6778866",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/AssetManifest.bin.json": "265e2c4c1faa58a843a417c65f6db0b7",
"assets/fonts/MaterialIcons-Regular.otf": "fa03b90f8c6adde6c7a86bc05eba4b62",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "f2a81232a8783811e0ff756fd43521de",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"index.html": "f15d6a14a24f8db073ffeab35694331c",
"/": "f15d6a14a24f8db073ffeab35694331c",
"main.dart.js_534.part.js": "8fa819be1594d40e5b40ce31658b61d7",
"main.dart.js_805.part.js": "c86e8a1630abf4bda1f106325857b3f4",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_803.part.js": "9d247ac5e1ce1726e456711625fa7da9",
"main.dart.js_441.part.js": "e67b95622616b0cc97900afcc7fa002b",
"main.dart.js_411.part.js": "d2f2674e4f02a5e5f2203f92e4e52b27",
"main.dart.js_498.part.js": "b17c2d51e0e783540f836e71ee06c253",
"main.dart.js_328.part.js": "494578fedc76b9a8096f6588ebeef479",
"flutter_bootstrap.js": "e15bcfd6ac0f88e9d34041cb1cc4cbbb",
"main.dart.js_810.part.js": "15942b9a3068718f59577c8ba9f2636d",
"main.dart.js": "ae4fd5ae5c3885f4406af3cb74f63daa",
"main.dart.js_614.part.js": "5bb6aaa1bc2052f666b6888809e26e4c",
"main.dart.js_672.part.js": "13fa5cc73e443f8c72dbe419c3c9a269",
"main.dart.js_815.part.js": "d3e7d959c0f7351dda864ef64579c5cc",
"main.dart.js_758.part.js": "0b9bfb143add69b907f8bc8b8b0ff2d6",
"main.dart.js_169.part.js": "fd9b3959061e57fa902a350131e56149",
"main.dart.js_145.part.js": "4b82fc691ee3c0e99934e8becc189869",
"main.dart.js_2.part.js": "c8fc2852582fed4628887e0c62964ef9",
"main.dart.js_817.part.js": "dd7dc5ca04fb54febc56eb3b4c4b6dfa",
"native_executor.js": "2dc230e99daa88c6662d29d13f92e645",
"main.dart.js_637.part.js": "5f330082285d0143bcdd379d3d0c9165",
"main.dart.js_813.part.js": "751626e211b17b05a4364027cd9e0a98",
"main.dart.js_760.part.js": "dbd4c2ff020755d12ac7988749445fca",
"main.dart.js_755.part.js": "51c2f223167273736b039ce8098b9204",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js_670.part.js": "4269b656417eaf4d30cad629ab8ebd16",
"main.dart.js_163.part.js": "e6e61e004f3a92c92524c5461b2da88c",
"main.dart.js_659.part.js": "249f246c1a2f910d88a07defce645249",
"main.dart.js_440.part.js": "874a6f3d3c5379e43390d40a01e568c6",
"main.dart.js_777.part.js": "af7c437276d752d1d04dfacb6c45527b",
"main.dart.js_786.part.js": "42935b09ccdd954e58d25a6bb9264200",
"main.dart.js_573.part.js": "a4e77bb142cf32bf4cfd89929a4eb9a4",
"main.dart.js_611.part.js": "0d9dc1a8e6b1b0a485856366dc73417f",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"main.dart.js_782.part.js": "b37bc79769894db203af9bcb291f091f",
"main.dart.js_27.part.js": "0b0daa755f76e8e2f3a4284163487697",
"main.dart.js_772.part.js": "bdf75ddff0315a450514de26fe79424a",
"main.dart.js_261.part.js": "6dbbaaf6514624670aad99c6eac1bb10",
"main.dart.js_816.part.js": "8bedc58baae758d45688790bcbbe083f",
"main.dart.js_747.part.js": "2c96ce1dab312348c5782156ac96e7e2",
"main.dart.js_793.part.js": "f857838998867fd3484b96780605f37a",
"main.dart.js_812.part.js": "2e1a891d572a753f85aee22119f23a2b",
"version.json": "a212cd2f9d443182258cbce594cf9e39",
"main.dart.js_796.part.js": "b7d82aa1e6d917afed24985ba203552a",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_149.part.js": "7598b9bf42d9063b8d2237bbc5b64c09",
"main.dart.js_195.part.js": "5173a11ad3ac67374391a6b7395ab80a",
"main.dart.js_654.part.js": "4519200ea5bba82ebbddd7604f04cb78",
"main.dart.js_808.part.js": "bba403a114864cfa3c66cbcd7c6f9d46",
"native_executor.dart": "97ceec391e59b2649e3b3cfe6ae4da51",
"main.dart.js_736.part.js": "6b33cf173d2cde1e1d51eda27fe3f3e8",
"main.dart.js_597.part.js": "6ecd445eefbd17bba0b702fb4e1b0fc6",
"main.dart.js_762.part.js": "cdfb2c8a1a265ae2389b700395c0eb9d",
"main.dart.js_818.part.js": "502edbdeadce434735e70f2eb7a0675d",
"main.dart.js_709.part.js": "a0b0fa5f6f88b07b0de551d9d1566ec5",
"main.dart.js_811.part.js": "503df353d585091f05ae6ebda7aae9b7"};
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
