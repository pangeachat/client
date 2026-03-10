'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"native_executor.js.map": "d917b10ddc99ffc18ed6d69299dee132",
"main.dart.js_451.part.js": "f15aec1f2e7d7672b0c850b1621f4d95",
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
"main.dart.js_681.part.js": "4327d1947db4efbabc7a9a493f8adae0",
"main.dart.js_271.part.js": "7deadcde6a34ae94841d45a32e2dc7a3",
"main.dart.js_624.part.js": "0ae9ae4ca04e9f4b52614141d51cb328",
"main.dart.js_205.part.js": "b92a44f20fc6dc8d1994db9728327ea3",
"native_executor.js.deps": "1ed982fbb5a994028ca7f51dbd855fd0",
"main.dart.js_1.part.js": "7232e61511cbae196f660a0ecc7ca1ed",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "0b70f89b4d0ea50fd78aa2ca300c4b92",
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
"main.dart.js_647.part.js": "340e88a8a8a44875b8d7c5baaf7f804c",
"index.html": "65907cbb610e6879e7ff4ce54ef44071",
"/": "65907cbb610e6879e7ff4ce54ef44071",
"main.dart.js_787.part.js": "d6bed696a1c58ae92146d26d693cf4bd",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_803.part.js": "a621612d00c5016c32bcdb5911299658",
"main.dart.js_827.part.js": "d1ccc8471de7e790f8ac77d61b0a81d0",
"main.dart.js_806.part.js": "ea951c4a97e623c7d558bb80ef674d17",
"main.dart.js_638.part.js": "1ebca5a29e3417e2af808042c1f2358c",
"main.dart.js_770.part.js": "a035411dc9da94688f8fcd7134fb03d3",
"flutter_bootstrap.js": "b3225d6b4aba366a0c147fcfcac46677",
"main.dart.js_508.part.js": "96523790a97c163d87d9aa0bf8e749f8",
"main.dart.js_757.part.js": "ea0cd3303e9dd3843c52dec32ebb4ee4",
"main.dart.js_810.part.js": "d9114f2b08bfb705931ae77a7e81f22f",
"main.dart.js_421.part.js": "5c483c41f3c6abb485030b9fa2937b52",
"main.dart.js_682.part.js": "3c23f31f777f99602a1eea2b66c2820e",
"main.dart.js": "9d8676e774f2a8f3c61884f7049cb45b",
"main.dart.js_815.part.js": "e001631faf486d5edbbc296f83235623",
"main.dart.js_2.part.js": "c8fc2852582fed4628887e0c62964ef9",
"main.dart.js_765.part.js": "17aae932fcfaddf1f2c8fe7545c01a60",
"main.dart.js_719.part.js": "9d551b691ebaff8feea38fa9137f1a84",
"native_executor.js": "2dc230e99daa88c6662d29d13f92e645",
"main.dart.js_813.part.js": "f8056f0c9a620622d4485bf7b6ea6a0b",
"main.dart.js_727.part.js": "6e5a7b1f66e0bb7650c72f5849a978af",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js_664.part.js": "dc1ccab57f0a79cba958fbcd388d7f05",
"main.dart.js_583.part.js": "b360c293fc97cc92e19d7da46726b09d",
"main.dart.js_152.part.js": "faf5906326ce476e8b90d8a4b512729b",
"main.dart.js_669.part.js": "ee1185532f048ad8dbaa7b8f462e20fb",
"main.dart.js_680.part.js": "91646d1e0ed94482ed35261c0103c5fd",
"main.dart.js_825.part.js": "c4eb0d9bf68f4aeb0eb613ffe3f6bdc5",
"main.dart.js_148.part.js": "39d8ada8df5abf8273e121d1749b992f",
"main.dart.js_338.part.js": "c5fd0c00f883ebfa8b6b4a01fd3f81a8",
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
"main.dart.js_768.part.js": "ea9048416b055815b772656c6f06d50a",
"main.dart.js_828.part.js": "981d1cfccb29548e9588d15b3be5ae4c",
"main.dart.js_166.part.js": "e106ea4faef02f20a295ac7d2928f752",
"main.dart.js_746.part.js": "026363d48d0f5201ac7cbc4226e7afb6",
"main.dart.js_782.part.js": "d0ea6a83d033d788e30a7ffef433cf4c",
"main.dart.js_27.part.js": "0859da5a167d80c7aa1337481eebbd69",
"main.dart.js_172.part.js": "00b345fa9453524366f2b04cb95062d0",
"main.dart.js_544.part.js": "73fc00bd3d1258cb51f0ce739bf6470c",
"main.dart.js_607.part.js": "a8dee50b4d75145e008c5cfd0423a21e",
"main.dart.js_772.part.js": "dbea2076fe36df2b354b5d3a1673f067",
"main.dart.js_820.part.js": "471d5cad21fddcde75ea93cb6754bd56",
"main.dart.js_771.part.js": "d582924c059d2151a49d4ce57bbb8661",
"main.dart.js_826.part.js": "c741b74af81be4840b82c10bfc0add5c",
"main.dart.js_450.part.js": "c952b8480bafe75271ffc38f86b9ef6e",
"version.json": "69462fbe1b7b46f39e932800f8d28f40",
"main.dart.js_796.part.js": "ce612607ce74695b8842563de9c42388",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_821.part.js": "dc43f2a9e51233e3a074c5d8d0c72098",
"native_executor.dart": "97ceec391e59b2649e3b3cfe6ae4da51",
"main.dart.js_822.part.js": "a85a517a24f088a5837e486b1003e9f4",
"main.dart.js_621.part.js": "95336bd0685ea652f74f6ee54dbcfb44",
"main.dart.js_818.part.js": "4deb5aa44a031dc752b426cbd30e6c3a",
"main.dart.js_823.part.js": "b547f42d2a07f4e0116c311deeeccbf0",
"main.dart.js_792.part.js": "86e8759ac673e8b666ee7d7daab93162"};
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
