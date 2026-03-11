'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"native_executor.js.map": "d917b10ddc99ffc18ed6d69299dee132",
"main.dart.js_451.part.js": "6387ea9f0f595edc475aca1e50acba9e",
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
"main.dart.js_681.part.js": "20eddd11e5cb5d5d6a69d12d0eb8c61f",
"main.dart.js_271.part.js": "31116b92b0ebb4898fdde68b870110c5",
"main.dart.js_624.part.js": "e8d3e602a5c4a378cbf854b92e47b45e",
"main.dart.js_205.part.js": "3b15de1ef6e7b93861723b33daf645dc",
"native_executor.js.deps": "1ed982fbb5a994028ca7f51dbd855fd0",
"main.dart.js_1.part.js": "edfee6fc5396ede358d0081e7ed38ad6",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "880804a5f8d45fbd728d320efb6c0b29",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "c258431f1238f969749d76801987b0f0",
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
"main.dart.js_647.part.js": "8ccff57573a135c734e6fcb9a5a8e097",
"index.html": "0fad695abf148ab02fc98c5b2f652de7",
"/": "0fad695abf148ab02fc98c5b2f652de7",
"main.dart.js_787.part.js": "3aeaaadde5c445855d7db43e47af2811",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_803.part.js": "f19e519ed434a63cc5ffddfe8ae5b627",
"main.dart.js_827.part.js": "22f311451d23e46a979ff2679fe4b363",
"main.dart.js_806.part.js": "1301ec35d780e3420670488b15c8a70f",
"main.dart.js_638.part.js": "8000584f8c1973f8e07281a9e41a7144",
"main.dart.js_770.part.js": "8648b957fd664880cb17399a43f993f9",
"flutter_bootstrap.js": "e336c7f800614cb8b7639aa1cbf910a2",
"main.dart.js_508.part.js": "91e6cfcd2fd49b5cdb22a80c5e4d6137",
"main.dart.js_757.part.js": "1f259453798c5168e4109220f46bf3d8",
"main.dart.js_810.part.js": "182196d1a21b1fe7d0adf2de63ec7910",
"main.dart.js_421.part.js": "79e11ce3f84e59a866ac52de522cb513",
"main.dart.js_682.part.js": "8a0142376d1f4e73049007b7836492db",
"main.dart.js": "4b22aa599d7411bdadbabf1398b4166e",
"main.dart.js_815.part.js": "e554b791521d4c10eab6692f66e00c34",
"main.dart.js_2.part.js": "c8fc2852582fed4628887e0c62964ef9",
"main.dart.js_765.part.js": "b9472d6086c3ac22eed68eff56f19dab",
"main.dart.js_719.part.js": "8af06a218c8194d68a75f5e4af0afceb",
"native_executor.js": "2dc230e99daa88c6662d29d13f92e645",
"main.dart.js_813.part.js": "fa4a0632ed47c3521591903f75b0ce2f",
"main.dart.js_727.part.js": "d3ebbc4268fd3529d2e754c041bb7995",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js_664.part.js": "667d6cba74484c773e0660521372781e",
"main.dart.js_583.part.js": "05eeaad5fe5eb8a32d7376e35c171b18",
"main.dart.js_152.part.js": "087fddda062d7ce63fda4dab45ac06e9",
"main.dart.js_669.part.js": "ee515ef77436ee4f86d34c999bf0a891",
"main.dart.js_680.part.js": "9d17cb92940b5fb1d12f5c6b81d14eb5",
"main.dart.js_825.part.js": "ee484fc920a194f307e93f5d61387d00",
"main.dart.js_148.part.js": "6ed88d513bf26e70b5d98f2f994a99a7",
"main.dart.js_338.part.js": "0d82608708ab95631abda241da65f819",
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
"main.dart.js_768.part.js": "f7e97cf3001c539942e447acd322547d",
"main.dart.js_828.part.js": "121bd21388da84ea6ce16e2b6455f29b",
"main.dart.js_166.part.js": "2ea01e80c63ee80a76796c2e08b288a9",
"main.dart.js_746.part.js": "3b8a5605e80c0f1f5d8d73e11fdfecc2",
"main.dart.js_782.part.js": "7e27a6b49fd5ea1ba5a80d2e5874180c",
"main.dart.js_27.part.js": "78ea41f378f29ee317fa8509dac5f915",
"main.dart.js_172.part.js": "34cb17dd8a240cfa7d8c3285a210683d",
"main.dart.js_544.part.js": "d6d51941b90eec2da52b6c07235c94d7",
"main.dart.js_607.part.js": "5c77c323c02ea97025a2a7d12ad8c7f0",
"main.dart.js_772.part.js": "d0bad13a229348f2af1a4f26f7f444c8",
"main.dart.js_820.part.js": "d82284ec72551e5c7596febbe4cda883",
"main.dart.js_771.part.js": "bfff7c648d6030daf12f773a74c8a2a3",
"main.dart.js_826.part.js": "c0201798bbef6f6ad460ace2d21d9c03",
"main.dart.js_450.part.js": "010890ba30a23fbedce7d5c973e82e59",
"version.json": "69462fbe1b7b46f39e932800f8d28f40",
"main.dart.js_796.part.js": "153ddfb817f983253883433be5b4fd3b",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_821.part.js": "da2b17198465f3e1a1c7ef9dd2338be3",
"native_executor.dart": "97ceec391e59b2649e3b3cfe6ae4da51",
"main.dart.js_822.part.js": "081e5a1f2310649e094bb51ee4085638",
"main.dart.js_621.part.js": "d8485aa8116df4a36dd719be1b2be883",
"main.dart.js_818.part.js": "99455af283e276503f53b9d8bfc7d217",
"main.dart.js_823.part.js": "d8f562026b28f5083dcd857e44572957",
"main.dart.js_792.part.js": "51b130bf9aeda9f7d18578a05813364d"};
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
