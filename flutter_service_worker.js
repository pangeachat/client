'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_819.part.js": "55df11fb5a68335ce538dcbe5a4abbdf",
"main.dart.js_605.part.js": "d2a7ae77a4b448da34605fb8931bc1d6",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"native_executor.js.map": "3b3c8585f85dd61ad1b5bff00c070435",
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
"main.dart.js_769.part.js": "514cf99c33b2593d8d0c2f4230ea758e",
"main.dart.js_744.part.js": "151012aeaaef2543e6d9a83e39c876d9",
"native_executor.js.deps": "10ac958717ea8858409e0956aa4d253a",
"main.dart.js_1.part.js": "1a541a12d6aeeaa7048188f110fe6863",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_717.part.js": "e79086ae169e07221d76d64c45e8ac3f",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "b74e4edf8cf7f5bc399e4d24198baa83",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "5b503a1b92431e8017837acdf7071cd5",
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
"assets/NOTICES": "feb313d4300c828f64ea331dfaeb44ec",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "d7d83bd9ee909f8a9b348f56ca7b68c6",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "c3121797cfb904346afab12190d119ae",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/AssetManifest.bin.json": "265e2c4c1faa58a843a417c65f6db0b7",
"assets/fonts/MaterialIcons-Regular.otf": "2b915c46a40142d64393a6622ef6557d",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "f2a81232a8783811e0ff756fd43521de",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"main.dart.js_780.part.js": "61a5f8ff0fea85b76741cda17293e147",
"main.dart.js_165.part.js": "bbc0842923124a71fcfb5507d68e2110",
"main.dart.js_763.part.js": "94db1cd4af251433aa38591222cbae6a",
"index.html": "2fb2aa2be34fd5acc98ea72bf7331ed8",
"/": "2fb2aa2be34fd5acc98ea72bf7331ed8",
"main.dart.js_204.part.js": "a812d6c9686604f868c6f89b95db57c7",
"main.dart.js_667.part.js": "573862e7db9cfa979a3df43c037c8238",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_336.part.js": "11841175c5dbdbf32c9067d087fab57c",
"main.dart.js_449.part.js": "cd39238bb4cd77891aa36167a12f65ae",
"main.dart.js_147.part.js": "5abaa5fb1b5f9eeeb4ca2572a344584f",
"main.dart.js_770.part.js": "a36cb0b29cb184c64ac8fca22c14a2cd",
"main.dart.js_804.part.js": "47bcd59b5028bffd9eedac525ba708e5",
"flutter_bootstrap.js": "5fa86d3f6a60fc29c6af2644a282e40b",
"main.dart.js": "801a6ca65ee6b78622f3a91ef9d12486",
"main.dart.js_645.part.js": "9afe5cba242a98b53c5b1ba8f9b7e25e",
"main.dart.js_824.part.js": "8c1ae6ddd440760a9328f8db220d5354",
"main.dart.js_542.part.js": "4f44781558376eed3cb2ccbc3cd9c230",
"main.dart.js_270.part.js": "76870674401b9d2db11f60700e4c0956",
"main.dart.js_448.part.js": "d19ffabd06a7e9655255dbdf704b3961",
"main.dart.js_151.part.js": "7929468aa0176e023b468d0242e6c0f0",
"main.dart.js_2.part.js": "c8fc2852582fed4628887e0c62964ef9",
"main.dart.js_678.part.js": "a9a6761eaa538a4fe5eb7e60d011efa0",
"native_executor.js": "2dc230e99daa88c6662d29d13f92e645",
"main.dart.js_813.part.js": "44d61fbdbc89d9fd6c71401c038f5753",
"main.dart.js_755.part.js": "11b2d2cff9bb92054a4d9ec4c2969439",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js_679.part.js": "a34d562bca931cf5626e21a5b01851b3",
"main.dart.js_581.part.js": "d97fef17a9f8c01cbe567686a690d547",
"main.dart.js_790.part.js": "1b3e4eec7ea7c54ce85b9d7662bf6867",
"main.dart.js_785.part.js": "a86c48fca87c8a4177434377193bd2bd",
"main.dart.js_619.part.js": "bff9890bcc01d4f14107f2ce26036d45",
"main.dart.js_680.part.js": "de62c931f4b2b7357826cc00f5560119",
"main.dart.js_825.part.js": "e1ec31168aac765cd5e489fa3c7129ed",
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
"main.dart.js_768.part.js": "b0a7359819a88ffa8b4457f37568c5e0",
"main.dart.js_171.part.js": "8a12c1896b9727595d7ced86ef149d05",
"main.dart.js_662.part.js": "12dd03e44c8b9e1905ab195b6650a8ad",
"main.dart.js_27.part.js": "90e1f94baa8e30db58ca8fae2151aff7",
"main.dart.js_816.part.js": "1786338493b2ef3d484b745d8a685a2a",
"main.dart.js_820.part.js": "00ae5d17d7cf54f5550ca63b8b474cd3",
"main.dart.js_636.part.js": "6efb8a1ed9c673e85cedf22950b0c00f",
"main.dart.js_826.part.js": "97d876a93f80cbbf03d02df3903ce9ca",
"main.dart.js_794.part.js": "931663c2c3255c5ecd2ebef119ee3047",
"version.json": "a212cd2f9d443182258cbce594cf9e39",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_506.part.js": "225dd2a215f2679825fea5afeb2e85ae",
"main.dart.js_766.part.js": "10326e6af170eed3276cb0d8f0003a57",
"main.dart.js_801.part.js": "b8d013c159f47e0477b06a98731b0a39",
"main.dart.js_808.part.js": "1547df70c66b240368e2459b9bb4f068",
"main.dart.js_622.part.js": "751922766919d5c42088879e65d07b00",
"main.dart.js_821.part.js": "9fd7efc3d4ea374b3a8c04e28f57b7e5",
"main.dart.js_725.part.js": "3a683b3ea8f18bce134e57d3d3efe6d4",
"native_executor.dart": "97ceec391e59b2649e3b3cfe6ae4da51",
"main.dart.js_419.part.js": "40826e30c145ed14adde3007ca6e16eb",
"main.dart.js_818.part.js": "937c91022c144b1ba1d04784044c9329",
"main.dart.js_823.part.js": "0c5f9a22021cf906f1b57681cf32817a",
"main.dart.js_811.part.js": "98d521af6db45569b5043cd0751548b5"};
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
