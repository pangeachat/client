'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_208.part.js": "4c2a4ccfe8496e752d820c51298cd006",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_259.part.js": "08815de240428308cf74aa8f5cff46a2",
"main.dart.js_243.part.js": "ad04aa3bed1fdd67a4341b6b6701cb96",
"main.dart.js_1.part.js": "d79eb2c26c52e7df87f16effc93e0899",
"main.dart.js_260.part.js": "efe4216dfcfe38c5d4c5603954d3a10c",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_245.part.js": "3252235239ad350e476bb57fb57672eb",
"main.dart.js_250.part.js": "ec0baeaa5c0a7eb7715a1eb36ca58540",
"main.dart.js_169.part.js": "36e47fa9a879c8356a1c906a9851f2dc",
"main.dart.js_211.part.js": "4e533d6b2e05e50cbad08e48c1cc7a5b",
"main.dart.js_184.part.js": "f0eca1e98805b85ac9a9e22934f76c20",
"index.html": "20f8a555f1856eb8ccd43b5493a595fa",
"/": "20f8a555f1856eb8ccd43b5493a595fa",
"main.dart.js_217.part.js": "9a3d39b9decb685f05846b0fa98d0256",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_241.part.js": "80979dda534602036d28ea07656a753e",
"main.dart.js_258.part.js": "46b18736dc9681e830fd4d48049a86f2",
"main.dart.js_244.part.js": "19cde4eaf4d84c61d942ead845bb4ac0",
"main.dart.js_242.part.js": "d4a9f3752070519ef8d510028227fc29",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"main.dart.js_265.part.js": "e966b87c2392f573869a2a176b63f432",
"main.dart.js_261.part.js": "c95280d5d117f0da479484f65e7ab95a",
"main.dart.js_262.part.js": "216943b253a8210c5de82a4fcb09fa02",
"main.dart.js_263.part.js": "9b3057c4b5ec985529135b3f1daa0175",
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
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "faf27bc559f85826a2bcf26f9879abe3",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "64814e9cab2cd64d62b79980036710cf",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "e98feeac93f6523cc0c1b0358ab60705",
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
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/check.svg": "e5130caf87a0a37b98ea74e80b055ffe",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/fonts/MaterialIcons-Regular.otf": "894503ede49c2c5b2a25c5614d16b2be",
"assets/NOTICES": "9f24b4d987496c2cc817fa20aa20cc78",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "d7d83bd9ee909f8a9b348f56ca7b68c6",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "6e2162f9214630d3a5396f0b9a823cf1",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"assets/AssetManifest.bin": "a9660d84aafbdaa38c1997e07b916f48",
"assets/AssetManifest.json": "ca0ab9c3bad77ab855faabdff0ce459d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"main.dart.js_210.part.js": "ea34b315bd42d4ba38542a3e757f6786",
"main.dart.js_240.part.js": "b05fecc75371cf957ff75bf6364ad711",
"main.dart.js_160.part.js": "32fc157ab3a171c78700382e8dec6d66",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_247.part.js": "5e7d308c75427308dc508cae66e69903",
"main.dart.js_254.part.js": "94ec451338b39ab56358a9cc6c8a5db8",
"main.dart.js_228.part.js": "45f281d05f493668d5336bbdc086d2d4",
"main.dart.js_205.part.js": "39ae93c9d802c27485463d2daf672dc9",
"main.dart.js_229.part.js": "8b003af8c4ead247196ca0947b72972d",
"main.dart.js_196.part.js": "56bffa262362651c5e374a206716714b",
"main.dart.js_192.part.js": "35c9ab4b1b2f2dd8e511b8dde3e3d2f9",
"main.dart.js_212.part.js": "7933dc8eae0d424c1031eebff1e8865c",
"main.dart.js_213.part.js": "add0b137e977c7f7a60f48e750d45922",
"main.dart.js_249.part.js": "12a92371d2d1c02effdc499549ca0dbc",
"main.dart.js_194.part.js": "4a03b3a691e91889223c46916102fbbc",
"main.dart.js_186.part.js": "6777768b28b91fc6037897cfe73f5058",
"main.dart.js_22.part.js": "034e120ae1504d695b188133202f863f",
"main.dart.js_158.part.js": "48cba969b6c82e362b6ec35eb1cda9bf",
"main.dart.js_255.part.js": "2e6da5dcd1b50de0737cd18c50c8aa25",
"main.dart.js_248.part.js": "f474d25f05aa7b38ca01ee4b607d721d",
"main.dart.js_216.part.js": "065d865440980fd7b9ee25099850d0a3",
"main.dart.js_171.part.js": "f0870ccb7498eb1a2511df4e325d9a6d",
"main.dart.js_231.part.js": "3ef9bfbe14f8db6a63bb06aa1cace3e5",
"main.dart.js_193.part.js": "4ad11389037533dd2cb3cad46109976a",
"main.dart.js_170.part.js": "b2efe7c418ffd760a50137a538eac718",
"flutter_bootstrap.js": "997bb239f2b2b759a38ee8007a2149a2",
"main.dart.js_264.part.js": "b79df3a216ca4c5a84f1403cc1c2895d",
"main.dart.js_178.part.js": "a9c68d4a50938acf4a95e0325cf2a62f",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_222.part.js": "ff619f6680587ec471ab5e226b924fec",
"main.dart.js_238.part.js": "cda7104a1d5bc4970f0015ed85f7c20f",
"main.dart.js_256.part.js": "ef578191c62b5068c7c95cd2404c1149",
"main.dart.js_221.part.js": "55a2a597e579c18445b27e1d85f3d05e",
"main.dart.js": "20dc2304f225899d96b80c2f9eef9def",
"main.dart.js_223.part.js": "4ebe72ce60b591619c27d96c151822fb",
"main.dart.js_236.part.js": "43dbc8a15b3247d7da75dc8b2e03bb3b"};
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
