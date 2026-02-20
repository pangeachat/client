'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js_812.part.js": "868d6166e7f60566a2eeda42af6f2a7d",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_716.part.js": "2580ad03878318e73f8b7601d540d4ed",
"main.dart.js_804.part.js": "241a3ff10691fe0cb8149fe2b718ce2f",
"main.dart.js_792.part.js": "3d80590ef681a749af85408312fcf26e",
"main.dart.js_1.part.js": "c43aaae9826bb335b64c08bd4033f105",
"main.dart.js_260.part.js": "1b826c57be550d174c9bc4783d237b1c",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_746.part.js": "a59e997ffb5f45de63643c923764072a",
"main.dart.js_27.part.js": "c0abee16a6c5783c8942a7ac8cf81ffc",
"native_executor.js": "2dc230e99daa88c6662d29d13f92e645",
"main.dart.js_627.part.js": "d318c6b587f072d1f04dc5387369c995",
"main.dart.js_610.part.js": "154e637a720a186b1fbce0cbf29cc582",
"main.dart.js_760.part.js": "73213d4ea65cdb04eea5b4adcaf91196",
"main.dart.js_169.part.js": "58d87f8cec18ec86939158557f981ccc",
"main.dart.js_761.part.js": "cc399d7b78def15f6b277627b5b78fdd",
"index.html": "feb17e64ab43b61daab5e8f78c217934",
"/": "feb17e64ab43b61daab5e8f78c217934",
"main.dart.js_613.part.js": "f4a875e704a6c819f8deb1b6244f24ce",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_533.part.js": "5a9a7872ab45d7390ceee4834082aaf5",
"main.dart.js_670.part.js": "f326c5b5e14613585ddf29a39470f933",
"main.dart.js_327.part.js": "77b79d282c504640de621ebd935c9579",
"main.dart.js_2.part.js": "c8fc2852582fed4628887e0c62964ef9",
"main.dart.js_149.part.js": "b249eba788ecd381adda5e77350ca568",
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
"main.dart.js_816.part.js": "abdb49035f2a489c3498de021a95a4f9",
"main.dart.js_781.part.js": "667a88bc3bab21ff9af61ceab8a67812",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "265e2c4c1faa58a843a417c65f6db0b7",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "f3c4a0d530594efb45bed836cab7a7c0",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "ff6884ddfdf1403183fb169677573361",
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
"main.dart.js_771.part.js": "54034b2b709b472ce4b07e0cb3a57f6a",
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
"main.dart.js_814.part.js": "7d04ab22d5f4f20c471eca19211e9bb3",
"main.dart.js_815.part.js": "89433c4391f947ee1cb95276feefa62a",
"main.dart.js_757.part.js": "01eeed6e47c6efe693ef2bb6e53493e1",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_776.part.js": "31b3b6214635af4d0a46b4b3c15991b2",
"main.dart.js_759.part.js": "8a0b74b5f30fb4619f788e642017b8a7",
"main.dart.js_636.part.js": "4386fd8410471e7a93ee23be276c124e",
"main.dart.js_669.part.js": "fd911b93a18bc2241bdf7581ff338788",
"main.dart.js_572.part.js": "019ea5618aed1b0fb9aca2a7a81f563b",
"main.dart.js_439.part.js": "7ea5d082c71ec6cdcd56f503c3d864fa",
"main.dart.js_802.part.js": "06de472784b7ef143662e64f8e536130",
"main.dart.js_596.part.js": "0726172f57865e6270bc1d5f57609030",
"main.dart.js_754.part.js": "ed528aa6f8603f2625655d2592563dd9",
"main.dart.js_809.part.js": "13ec6388ea15dc8f489b5cb104dbd1d1",
"main.dart.js_811.part.js": "0cb64fca013f3cb075a1bec24c74c3a8",
"main.dart.js_194.part.js": "e808473632557608ad709a5ebe0f1a87",
"main.dart.js_163.part.js": "ba8d3841d1cbb2bfc239fd1f9a8153f7",
"native_executor.js.deps": "d3b2ff826b8f04a8a253a7b1bbee99a7",
"main.dart.js_735.part.js": "7969e3d57b4aefa3d86125c061fe6ad7",
"main.dart.js_807.part.js": "8a7f285f84dfffb08d8b25089bd5483e",
"native_executor.js.map": "4081a54baff3648428eaadba1e99f99e",
"main.dart.js_497.part.js": "03f0516980676bc24b66be49e9983498",
"main.dart.js_799.part.js": "f4ea15e52fdafea25ee6764a0181e2e9",
"main.dart.js_145.part.js": "8a9dbfa147fe232c4c99e7d9d9ba633e",
"main.dart.js_785.part.js": "e21d7d603b26ca9d23b23d583a25c2d4",
"main.dart.js_810.part.js": "b414e0881ca899094ce569424506fcce",
"main.dart.js_817.part.js": "0e401940a351c53ad89cef64ceaceec1",
"main.dart.js_708.part.js": "97aa544de8522e09714b1bc4293915fd",
"main.dart.js_671.part.js": "19c17ae7bee27b23a089092b3f9eaaf4",
"flutter_bootstrap.js": "70d3bdd93c4a9b7a070db2e67014bcc2",
"main.dart.js_795.part.js": "020ed1cc4667e496c6128380c7badfa3",
"main.dart.js_410.part.js": "8bbb30ebef6001f87ef42753f331247b",
"version.json": "a212cd2f9d443182258cbce594cf9e39",
"main.dart.js": "978ecd95333084b89a9f668d2a9ba919",
"main.dart.js_653.part.js": "29a4adc32315c48c982117654d828a01",
"native_executor.dart": "97ceec391e59b2649e3b3cfe6ae4da51",
"main.dart.js_440.part.js": "fe2f5d57bde6b23e64f4d7078f5ddeb9",
"main.dart.js_658.part.js": "643534dca26ea1d572b8046144208230"};
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
