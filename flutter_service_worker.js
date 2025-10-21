'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_657.part.js": "c2e152cbcd78393e3fe5b6185493a687",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"main.dart.js_135.part.js": "42f260d7d2d6ed99e13d6cc4e0c69919",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_640.part.js": "61d18ec9620a755085aa657c03ccb482",
"main.dart.js_621.part.js": "c11364f281b24862790a03f894eda980",
"main.dart.js_513.part.js": "77f1aa2a919a93f7bf33dc28766ed5f5",
"main.dart.js_1.part.js": "cf2039080dc87ad067c1c67fe85751e1",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_616.part.js": "0ee096234ee4dfb62c327838bf1e94b7",
"main.dart.js_368.part.js": "817ee7669c0a71624c164a55e385fedf",
"main.dart.js_610.part.js": "502c5babf15592bfdacf72053b0b0d7a",
"main.dart.js_540.part.js": "0038504b65148e0c81669b94ed0226be",
"main.dart.js_632.part.js": "0949e24a1b438dac2ae2f3733c833766",
"index.html": "c354d845c058ccab1401a33328099a44",
"/": "c354d845c058ccab1401a33328099a44",
"main.dart.js_601.part.js": "2f4d7aa46af85a5a166e9fe05063491a",
"main.dart.js_646.part.js": "7dfaaa681ba586823788690b3859f184",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_522.part.js": "d396197d490565bbc907762f9a47b8bd",
"main.dart.js_480.part.js": "bea25399741ad398d0c84c3a44cfeb71",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
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
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "9357c76127444b43171bafd2614b3485",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "3bf888040a3a4aab43d4c59b8307c58e",
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
"assets/fonts/MaterialIcons-Regular.otf": "8cc02219ab078c92c26e2309f83eb988",
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
"main.dart.js_667.part.js": "23601add8e2faf840c96c9d6c05586af",
"main.dart.js_210.part.js": "6920886368e07be57e7aa7262295509c",
"main.dart.js_664.part.js": "ec6d52554edd7aa850f4068955e0c9c3",
"main.dart.js_369.part.js": "ce24c32e81d935002171ca1c58ae4dfc",
"main.dart.js_554.part.js": "2028ab1f1abf553d1970c823cc518bf0",
"main.dart.js_659.part.js": "4d667a9cec8e552cc794ce71aab1f01c",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_512.part.js": "33e687aa993c4151dfa9c2140bf1089d",
"main.dart.js_649.part.js": "f07bece2b3565649b437868ef449b9c4",
"main.dart.js_669.part.js": "69122ccf72f5872cf4410d394470ac41",
"main.dart.js_618.part.js": "f1c873f6f8152d3bb9a787112a0d55bf",
"main.dart.js_666.part.js": "c586251b2c529e8c7e22e71842f9c213",
"main.dart.js_154.part.js": "ca82a84f03d4a19d6a94370b398d2ef3",
"main.dart.js_622.part.js": "160f54ce645de0d5dee027b96386f303",
"main.dart.js_142.part.js": "fca295b6e02542ff2d717600852d8fee",
"main.dart.js_527.part.js": "b4ee4cf2d28bf9de770447a7e5b3c857",
"main.dart.js_553.part.js": "16f3e2660baa5c6f380392435352e00f",
"main.dart.js_628.part.js": "e3db8aa1a5b8d70563744062d80486ff",
"main.dart.js_131.part.js": "a74fd72b822872492fdccde73cd6ba66",
"main.dart.js_269.part.js": "cf8f5e03bd7a2f4369bfd3eb7fa330ec",
"main.dart.js_543.part.js": "25c5689897cf9cc2e806481bb3fdb93f",
"main.dart.js_500.part.js": "81f046be835b376689b7d9f21af0fa36",
"main.dart.js_654.part.js": "6ee26a86bfd0441c5a9c373dc6e7904c",
"main.dart.js_665.part.js": "0df6e349574768017b89302b0d3679f5",
"main.dart.js_342.part.js": "2df50328ab85038010bad9edc690884b",
"main.dart.js_24.part.js": "6e215785f05e22b2c2830343f037981b",
"main.dart.js_145.part.js": "d15167c28b0ff1f4471ce564c659877b",
"main.dart.js_662.part.js": "8f06faf1e3427c646bc79c89059a7323",
"main.dart.js_582.part.js": "0d06bfd4ac10beab49d7c7d3b198cff4",
"main.dart.js_588.part.js": "4066f2f139e58b66e95864cf617ff790",
"main.dart.js_444.part.js": "b127a70c8abb0e0c13388843cec84efc",
"flutter_bootstrap.js": "86413fd19931cac8ca0df331c23bd0c7",
"main.dart.js_637.part.js": "2f514fc947f60e0e34a041d13d872f80",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_663.part.js": "e26cfb58cd44ccd7b21660d45fab89df",
"main.dart.js": "234ef0565492e021c203836e9fa298a6",
"main.dart.js_668.part.js": "4e82afe58d6886f1222d1c34228268fd",
"main.dart.js_552.part.js": "f2da5ef732da283af1ebdccfedb11497",
"main.dart.js_426.part.js": "fb38d5c0a8dcafb83ec080fc033388b1",
"main.dart.js_620.part.js": "a7defd7305af613791b349fc3fff8990"};
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
