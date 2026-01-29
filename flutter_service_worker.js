'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_739.part.js": "5a0e08f0e51da3ea87a5402c65ccbc44",
"main.dart.js_619.part.js": "37fcfa9fdd93367e500ac385c3a7e47b",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_597.part.js": "cc7b56d95d417eb52cb35ba955c87740",
"main.dart.js_716.part.js": "8f9fb65b7faff55544ef2ac0420e49d3",
"main.dart.js_1.part.js": "5aca397fb87a28114d0cd7193a1cf59f",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_758.part.js": "53731427c9ac9c21103fc061a0163177",
"main.dart.js_704.part.js": "3340ea4d7cf2693abf09a1936e2ce20a",
"main.dart.js_767.part.js": "0a98d09b1a27e3a2aca036693ee2a5b3",
"main.dart.js_746.part.js": "2e6a71a82e59971e92a0b3d6b8ad7781",
"main.dart.js_764.part.js": "523875b4e1fce9389770a726ca7dd5c0",
"main.dart.js_694.part.js": "3a78ddde0c50d344ebe27658cc0e65cf",
"main.dart.js_725.part.js": "38efc7fd1b706bdf672a693cc5ebb51b",
"main.dart.js_766.part.js": "362839835920b4d71f1d7e5924a88ebb",
"main.dart.js_140.part.js": "730410e084e95eb5e58aab29f17d7e4f",
"main.dart.js_749.part.js": "b566b8aa02266b1f577228ca0bce507a",
"main.dart.js_184.part.js": "c968c9917a0c8008282829307e9ee6d6",
"main.dart.js_761.part.js": "233d98f4d76cbefac8a49c006b15334d",
"main.dart.js_624.part.js": "a83054d35e7bdaaec719feac778ab257",
"index.html": "bfd1d01bb63e0ba8a1115cfb18dd2967",
"/": "bfd1d01bb63e0ba8a1115cfb18dd2967",
"main.dart.js_583.part.js": "31a46cb0dfc78dd3e29c9ed78f011672",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_244.part.js": "1a705b24248a4555f47dbe39910643bc",
"main.dart.js_756.part.js": "1f972328255213af06f4818734c31684",
"main.dart.js_713.part.js": "bbb7c80e4c37def75a256db8e4d3aa70",
"main.dart.js_2.part.js": "7cee2287ac1678f9fb9a62c555b7f31f",
"main.dart.js_717.part.js": "cc5e2b41294fc07bcae4fa0a377606ed",
"main.dart.js_418.part.js": "48f47f1e170f6fbc4f49c555499e558f",
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
"assets/AssetManifest.bin.json": "265e2c4c1faa58a843a417c65f6db0b7",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "b477e6e03d77d74d108fad0ad2a687d0",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "7f4bdbd9c59d42100e883d30b6d84105",
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
"assets/fonts/MaterialIcons-Regular.otf": "20cc7acb062efb181601049d45114775",
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
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "4798b9f8e2c5c4eddb9dcf5459140218",
"assets/FontManifest.json": "e8ffcdb543de3457df4202315dd59741",
"assets/AssetManifest.bin": "f2a81232a8783811e0ff756fd43521de",
"assets/AssetManifest.json": "ac5e8711684d70efaa75ed0c9717a31b",
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
"main.dart.js_548.part.js": "70ef91486ce8560ea8d91472c64c3f28",
"main.dart.js_635.part.js": "c5a94a15602ef2da15141372e49e2109",
"main.dart.js_474.part.js": "6e332d6aa759a204eed476a7c084d22a",
"main.dart.js_164.part.js": "7255f6db9e70e6d133794705a42ad475",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_636.part.js": "03ecd1ee2916c474b13ec1bb2f4bab3d",
"main.dart.js_762.part.js": "25425300dd933345bdda76d298f6cbe3",
"main.dart.js_569.part.js": "475c5d22a01274dc65d40cc7ebf4de72",
"main.dart.js_669.part.js": "5644bc39f1cf1e96201a0ec26d3491a8",
"main.dart.js_389.part.js": "7bf689cb3e638ea0130d3cc6bd82f61a",
"main.dart.js_144.part.js": "12abe01a72ffa32d56393f8eb6619699",
"main.dart.js_604.part.js": "56f8e7254a00d2f5ff037ea51d1b99d3",
"main.dart.js_765.part.js": "d558287986623058443043bcd10b81dd",
"main.dart.js_309.part.js": "5574f270e126facb3753d4a3f0a832b2",
"main.dart.js_417.part.js": "5318ef375cd74db094feb58a3203f210",
"main.dart.js_158.part.js": "b5b7999e767afa56f72b26a5dbe91168",
"main.dart.js_509.part.js": "d2826c3b7567e8dc7b33fa2e4ec4e549",
"main.dart.js_753.part.js": "8c0bf6b94510b5279d676fe1b1c87338",
"main.dart.js_735.part.js": "23b56578b4f9b1c2647a5fd81a694734",
"main.dart.js_25.part.js": "9a0beca2f095b4f5443077203e684451",
"main.dart.js_763.part.js": "bcc3ecff567856f7539be8012ccc8231",
"main.dart.js_676.part.js": "4e4318c76f600dfb49b497af7eb5e8be",
"flutter_bootstrap.js": "9903275f575fcc06e966a490a385e240",
"main.dart.js_637.part.js": "f5588e2d2954ccd77e85a06728bc83eb",
"main.dart.js_711.part.js": "fc5755e4664bea9a292e170c38d05b78",
"main.dart.js_715.part.js": "e8aed3c5e50dfe390ecfb860e4506d27",
"version.json": "0e33d8419087795f035b918bcf15b567",
"main.dart.js_585.part.js": "2c61b49d04dfadf45571bbc6c7ddd9bc",
"main.dart.js": "908d4ca9baf9a54364097a6d96fd5d04",
"main.dart.js_730.part.js": "b724bbe4826aec008de03ec6c871df56",
"main.dart.js_768.part.js": "40f3dc7c2374e6ff1a16b84fec59965b"};
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
