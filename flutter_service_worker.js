'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_208.part.js": "f55bca064e43c02fbcbacc5d3e443d63",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_259.part.js": "c355edbe511843f426a5f59521d3b317",
"main.dart.js_243.part.js": "25f9609a54c34eeeb8dbaaa30a15a6db",
"main.dart.js_1.part.js": "2f100e4833e4807b68c0024506e59145",
"main.dart.js_260.part.js": "717de0631e4adc7ccba70b82651c2eb4",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_245.part.js": "c149fdf339840ae0df8b2bf7fab6f298",
"main.dart.js_250.part.js": "7b794a70c2ea3bb7dacbb9adecbdec41",
"main.dart.js_169.part.js": "0d5eaef87de400e068c772a6c850fa8b",
"main.dart.js_211.part.js": "178fdab28e24b4967a181be376fa849e",
"main.dart.js_184.part.js": "4a7387ef5f33ed351acdd794c0569852",
"index.html": "e75d1bc476e40124eec3585173b539fd",
"/": "e75d1bc476e40124eec3585173b539fd",
"main.dart.js_217.part.js": "b611b924a2d244e922d751507d326cff",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_241.part.js": "1871b72d33b7f03b5f3a9e3c7e3cb08d",
"main.dart.js_258.part.js": "309a20d741e5d1b343d60ee9b1b133d9",
"main.dart.js_244.part.js": "d1c2b9042558e4142702b7b256c4ca8a",
"main.dart.js_242.part.js": "0f88b3279dc30eccc206cde29b1e297b",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"main.dart.js_265.part.js": "52c3be9046907467a939f861c8dac5df",
"main.dart.js_261.part.js": "ed1f31c850fadb18b871578135307676",
"main.dart.js_262.part.js": "d1d91f6441c820bb15b8110065d2ee1e",
"main.dart.js_263.part.js": "3699c2676e19c1a1133fda6b0f3dfcec",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "53d35b32b7b36bc440ba8f6f17ced0b2",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "311b3b7ca265fae3c2670e4d85573915",
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
"assets/fonts/MaterialIcons-Regular.otf": "0dadbe403614885e29e90d0e48b93667",
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
"main.dart.js_210.part.js": "99bd614011ab32367d51b8b807c8f27a",
"main.dart.js_240.part.js": "cb770427cf2fdc6367cc7cd4545c7d54",
"main.dart.js_160.part.js": "0071a3d3671581464639577d5af73ea3",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_247.part.js": "363572fbf5dfd3307e26ddd04dc27df1",
"main.dart.js_254.part.js": "25c2c510c39bbf582842ad7257286f96",
"main.dart.js_228.part.js": "3eefdf4fab33b80ed5188e356877f2c3",
"main.dart.js_205.part.js": "0dae071f76a8ce03e580b57d494809c8",
"main.dart.js_229.part.js": "a36d63e6e62bb267879eaf1be40e53fb",
"main.dart.js_196.part.js": "7f4b3d79c2236c93238bf436a72e8eb0",
"main.dart.js_192.part.js": "59802630b985e14d464d96a145e84e06",
"main.dart.js_212.part.js": "e4e6967bba850ee271b55460cf798187",
"main.dart.js_213.part.js": "8aae1211760c60235422875345dc7543",
"main.dart.js_249.part.js": "54fac0a0fe1fabc159e7e666de50cf22",
"main.dart.js_194.part.js": "e88f740b5874717fb5462ac8166a6dfe",
"main.dart.js_186.part.js": "7870f94e77846147dff5617f9ea6d925",
"main.dart.js_22.part.js": "80e89e26e8869e7584c14f6340dd0bb3",
"main.dart.js_158.part.js": "757ece7db0b40bb912c2b3c59d8f3fd9",
"main.dart.js_255.part.js": "0f03a81631ec9960c3cb209d736fd60d",
"main.dart.js_248.part.js": "bed41cd28079a572225b5c21217a1d86",
"main.dart.js_216.part.js": "a0d7b20fc8107e8e16166949f3971e33",
"main.dart.js_171.part.js": "a4798378ccd150eb909c79e1ec6b37b9",
"main.dart.js_231.part.js": "b8a9fd27c2615a2384c0a6e5151e10f6",
"main.dart.js_193.part.js": "fbb25e3fbb8b51bb756092134b421d35",
"main.dart.js_170.part.js": "c5e012cdd811ae7130d522f2ef331d1e",
"flutter_bootstrap.js": "f72d4f0b6f09f657a4a45f9d262a11f2",
"main.dart.js_264.part.js": "43e8f264ed52363d9746b49177dc76bd",
"main.dart.js_178.part.js": "57a2beb1dac3db0a929495eab23faadb",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_222.part.js": "2c4ba1381fa04712c71b1d0f13718b7d",
"main.dart.js_238.part.js": "de551bafca0c3d72d8fbbe7c1a3f4e1f",
"main.dart.js_256.part.js": "c5c64e1d3cf0ae92070de56db587f4aa",
"main.dart.js_221.part.js": "3cb8a7c7163c5f8a6dc9c204756cab21",
"main.dart.js": "a4f17066d36b0d4b4b0d1327a23d6b15",
"main.dart.js_223.part.js": "3fc8ddba8543ed4da1f9ef751f344164",
"main.dart.js_236.part.js": "f2d087f6e6b8e1bb0fa9825615f3737d"};
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
