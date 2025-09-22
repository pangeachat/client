'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_210.part.js": "ee7b9a3874d88345cdb57d03cc614e39",
"main.dart.js_257.part.js": "d7ce942b8b32c0688b81d632d886dddf",
"main.dart.js_267.part.js": "10b9857972e3f84a5ee1c27d5f166683",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"main.dart.js_233.part.js": "88cdbcb0a3fd76e457a7e3ccaafa5b60",
"main.dart.js_265.part.js": "17872be4d1faafff7d9f68081273e0b9",
"main.dart.js_22.part.js": "ee53fbf10490c2cb298778ae3bb738a6",
"main.dart.js_171.part.js": "53cf5b966a5b9b68de3102f0496ef421",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_263.part.js": "06cf9af7a6d5eeddf89d3c176ecd7d7b",
"main.dart.js_240.part.js": "1183afe3c8322a629a9167242caa484f",
"main.dart.js_231.part.js": "197d9336deffdd62a361215f696a4a73",
"main.dart.js_238.part.js": "d36e5077f06732dcd9546612c4ca16d0",
"main.dart.js_212.part.js": "f041237679fcfb5a99b3934f5d818845",
"main.dart.js_162.part.js": "40ef678c83eba5aedd5cba4de973a6c2",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"main.dart.js_252.part.js": "844ec9f0db8a8f0f50a123ea7fb34851",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_195.part.js": "7f04447b322082a123fa1adf6547a91e",
"main.dart.js": "b6458da63eccd0115f98f874912668fb",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_246.part.js": "19a817b50dca389fe7481c30cc5770e1",
"main.dart.js_215.part.js": "15e1efb25099322429e8117fea0cd399",
"main.dart.js_1.part.js": "75a3fd62377b43b5be440993f7d15de2",
"main.dart.js_261.part.js": "214febe8614288d47ae805d50137963a",
"main.dart.js_198.part.js": "5835e5de82589d1c63dbe328c6923979",
"main.dart.js_249.part.js": "0511ebb38fdb2dcece6cd75461e81a43",
"main.dart.js_213.part.js": "6d0565e6b2ae09351dbdf625a93e4451",
"assets/NOTICES": "9f24b4d987496c2cc817fa20aa20cc78",
"assets/fonts/MaterialIcons-Regular.otf": "8c3770e3c4aa6e2b54f26898787b93a0",
"assets/AssetManifest.json": "ca0ab9c3bad77ab855faabdff0ce459d",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/check.svg": "e5130caf87a0a37b98ea74e80b055ffe",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "fdbbaad27c0ee238f303e1090a5465ee",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "2974a5f289e951f3fd74bdb5c4e2a971",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"assets/AssetManifest.bin.json": "faf27bc559f85826a2bcf26f9879abe3",
"assets/AssetManifest.bin": "a9660d84aafbdaa38c1997e07b916f48",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "66cc89d41fa47eb765cef6b7a32e459b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "74e8a80a1b0f561fa1c2cb4cab72d1e3",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"flutter_bootstrap.js": "080f54d394480cfbd7e465a8de84f976",
"main.dart.js_242.part.js": "a8cef197c8cda4788ebf4b423f8996ff",
"main.dart.js_172.part.js": "b8d59cf9617a127ed1ba4820c38bf50f",
"main.dart.js_173.part.js": "dfaaa4f60da04f257eb7378ed4ffefc9",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"main.dart.js_223.part.js": "40aa7f3e5950248621c294b46c719d60",
"main.dart.js_260.part.js": "da6a70adbcb9b216be62bbc1d1ff39bf",
"main.dart.js_214.part.js": "deaa97e18919888f921ba9a2e8e3c9c8",
"main.dart.js_247.part.js": "9e9157531beb6107f8389e80f5e60e56",
"main.dart.js_244.part.js": "708d74fe93886fb0218ffff758084ad2",
"main.dart.js_264.part.js": "ebf4bbec6296bd9404ba9c41ea4e2088",
"main.dart.js_180.part.js": "de453c5404042a3a0c3c392d8c595fcf",
"main.dart.js_219.part.js": "a8cdb6befedddeafe406e61e551871ff",
"main.dart.js_196.part.js": "6c9c33f2c298b80bf2f76de38e76c870",
"main.dart.js_256.part.js": "34643184f741e65cf41defb9c1408e94",
"main.dart.js_218.part.js": "b7922cdc7bde934d55ac7d7496c35c32",
"main.dart.js_186.part.js": "2faa6b1dca20526408f7179f8633cd53",
"main.dart.js_250.part.js": "cddc0cb744cabd18ced2429755e976f4",
"main.dart.js_266.part.js": "4ee98633c3f686754bcaf2b95b21d1ab",
"main.dart.js_251.part.js": "9c899fd761407ce517447904665e7bf5",
"main.dart.js_224.part.js": "f1fce14b00be8ffc6907bc6d94a40544",
"main.dart.js_160.part.js": "88a2dc8d84c7b4b864616812805bf8b9",
"main.dart.js_243.part.js": "aa2a69e6d0716edd96885b749694f8d6",
"main.dart.js_245.part.js": "11fbb30f89faaccfc43e5a06049f32d2",
"main.dart.js_194.part.js": "82f64217ea316dac9d18cedb90274437",
"main.dart.js_188.part.js": "470942f1777698d25cbd7dd55787528d",
"main.dart.js_207.part.js": "0f0fd25b8c6cd465f8fda7f7c62f846a",
"main.dart.js_258.part.js": "775dacdd79737ee972e6b6a612c0417b",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"index.html": "2bfb717d09ec721e2939316a5eeab1a0",
"/": "2bfb717d09ec721e2939316a5eeab1a0",
"main.dart.js_230.part.js": "1353c9f837e1eff20d8e3aaa157a3d6f",
"main.dart.js_225.part.js": "58766e60b01b273b70b5a1fbb2446664",
"main.dart.js_262.part.js": "f4dc3df927633851a33ad5bc017c4104"};
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
