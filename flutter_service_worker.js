'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_619.part.js": "42f1ddc56a8728f6a8c4930371912743",
"main.dart.js_808.part.js": "978c977cf7a8ca6f98e5ad0e387498c4",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js_751.part.js": "b152409b0129904123b143db02d06457",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_640.part.js": "947483987518aa8cbb169dba637f9de2",
"main.dart.js_712.part.js": "80a0439c96c2fc3f363fa13c1e03964f",
"main.dart.js_1.part.js": "1373917aad0578e8e01560a42128e09d",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_784.part.js": "8b796b71364c17e003c36dca1394a5d0",
"main.dart.js_162.part.js": "aaacdcb6a3e924887fef0793e074705a",
"native_executor.js": "2dc230e99daa88c6662d29d13f92e645",
"main.dart.js_803.part.js": "141e030f7bbeb46a748ca3d9d1266821",
"main.dart.js_616.part.js": "4b888941e0cef55be5654e75d9919894",
"main.dart.js_602.part.js": "95949cb112f051a5c2519df001db5bd5",
"main.dart.js_791.part.js": "2e083cd08ae437592b1d16913bda181e",
"main.dart.js_672.part.js": "198facb8f4eb2787d8a053b1c1e6f729",
"main.dart.js_794.part.js": "b96380ca9ce884b0146703261e6213f8",
"main.dart.js_507.part.js": "5a367bc22dbe7f7ad887fe5eec2851b1",
"main.dart.js_633.part.js": "2e0aa048537e15cc5b694af94d812cfa",
"index.html": "8208b685b7f29394bd6765d99b9946bc",
"/": "8208b685b7f29394bd6765d99b9946bc",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_740.part.js": "b3038cb513c09d3af22c1040a6820ab8",
"main.dart.js_2.part.js": "c8fc2852582fed4628887e0c62964ef9",
"main.dart.js_177.part.js": "68ceb4852eaea205a41c75ea77d0de02",
"main.dart.js_660.part.js": "3923ad4eea08da2159b5cd1d4777a7be",
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
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_655.part.js": "609beb6f4e7b1377605ef7e7a51e032d",
"main.dart.js_777.part.js": "0e0ae1c2093254c11667e49b29105c4b",
"main.dart.js_800.part.js": "b9cad394ad756ac55abc5dddf706d379",
"main.dart.js_796.part.js": "c8a553765aa8c51d3719e168cb2fb684",
"main.dart.js_205.part.js": "b31ec936340dec3461c8ea6168c5ab49",
"main.dart.js_542.part.js": "b38d49c4b79bf102a43deb7e98ad7a3b",
"main.dart.js_787.part.js": "b59d0dade3875251d1b8074decf167ed",
"main.dart.js_802.part.js": "0d197ad634e1234a3db057ed069fc5ce",
"main.dart.js_754.part.js": "7be14d96e0153e5bce096d7afd7d96b0",
"main.dart.js_267.part.js": "abf0f013d2601839508167cab6532173",
"main.dart.js_805.part.js": "a356532ea3ca2cdc0155e0a16bfb626b",
"main.dart.js_748.part.js": "95bf843b2694521613cedf1bfb9d7052",
"main.dart.js_755.part.js": "8ad8c3aa2b906308fb84a79e7746c014",
"main.dart.js_581.part.js": "eabf3a741fdbad9d4f025255e849b0e3",
"main.dart.js_801.part.js": "1289d76cb2bf50ec8125ff68a5429800",
"main.dart.js_158.part.js": "b26c7b1e925325c34160fa5eff083293",
"main.dart.js_753.part.js": "426e9c4ab8ee753fc83c8c37aae347f4",
"native_executor.js.deps": "ed8fd28a0ffab55fcb94beb67958f24f",
"main.dart.js_806.part.js": "98219c8d323be7f7f3a02cbda8df5ec6",
"main.dart.js_183.part.js": "4a650dc6105776cd27db4e86639808a2",
"main.dart.js_332.part.js": "b4c39e26cdc322cc422cbd2187357888",
"main.dart.js_807.part.js": "19e568d59379c863b44a5462c42636ab",
"native_executor.js.map": "0f120249440b41114f93b0c72d252c97",
"main.dart.js_29.part.js": "fcb4391403e16b6bc5331728ce76d835",
"main.dart.js_673.part.js": "8b1d516d0a1e253e21ca642835319c2f",
"main.dart.js_799.part.js": "c8b92f8063e4acee485db3039e291904",
"main.dart.js_763.part.js": "6e44659a8c73a1ac134227b1d942b4f8",
"main.dart.js_443.part.js": "f52d3d9392c5e0b00a217719ca603aa3",
"main.dart.js_444.part.js": "412522965dfaae9d06173dcea1a6b638",
"main.dart.js_671.part.js": "b8d86d990adb75bad93d145757f04494",
"flutter_bootstrap.js": "de4daf0ce9d070370636ebbe0db699a9",
"version.json": "a212cd2f9d443182258cbce594cf9e39",
"main.dart.js_413.part.js": "6b63efcb329a7d21343c49a63091c16b",
"main.dart.js": "686c834ed6c4b2bc64d612d6ac1a20b9",
"main.dart.js_773.part.js": "1e2af6bbb6ebd713d27a528437b29524",
"main.dart.js_730.part.js": "7448568920334f814a14f719a6c229f3",
"native_executor.dart": "97ceec391e59b2649e3b3cfe6ae4da51",
"main.dart.js_705.part.js": "1defe7979699fcb0aabe8f2d38a23fa8",
"main.dart.js_768.part.js": "3ff736069fc1be5c325238687d45de8c"};
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
