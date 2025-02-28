'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_157.part.js": "802af6325f294679e5e64c6768162778",
"canvaskit/skwasm.js": "ac0f73826b925320a1e9b0d3fd7da61c",
"canvaskit/skwasm.wasm": "828c26a0b1cc8eb1adacbdd0c5e8bcfa",
"canvaskit/skwasm.js.symbols": "96263e00e3c9bd9cd878ead867c04f3c",
"canvaskit/skwasm.worker.js": "89990e8c92bcb123999aa81f7e203b1c",
"canvaskit/canvaskit.wasm": "e7602c687313cfac5f495c5eac2fb324",
"canvaskit/canvaskit.js": "26eef3024dbc64886b7f48e1b6fb05cf",
"canvaskit/canvaskit.js.symbols": "efc2cd87d1ff6c586b7d4c7083063a40",
"canvaskit/chromium/canvaskit.wasm": "ea5ab288728f7200f398f60089048b48",
"canvaskit/chromium/canvaskit.js": "b7ba6d908089f706772b2007c37e6da4",
"canvaskit/chromium/canvaskit.js.symbols": "e115ddcfad5f5b98a90e389433606502",
"main.dart.js_202.part.js": "b548ff4d8f1968b6993334e3db330123",
"main.dart.js_210.part.js": "5167c5cbbf0c6a6a6b7fd2b1e3398dc2",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"main.dart.js_170.part.js": "9fefc441ea7a1d65b5f5b28100bd70ce",
"main.dart.js_236.part.js": "741c38451549fee6f8cc0668bdfa5b2d",
"main.dart.js_258.part.js": "2d6d99814c3927f30b82733de06a3528",
"main.dart.js_254.part.js": "11064097f630aa0c16da9bc92e92ff56",
"main.dart.js_184.part.js": "23f8ae958cd6582c353f21cee94b4a16",
"index.html": "f9a6fa14656a0f7409db30d55af0d0bc",
"/": "f9a6fa14656a0f7409db30d55af0d0bc",
"assets/NOTICES": "7a487dfe518cda9a14b187cf465de387",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/js/package/olm.wasm": "239a014f3b39dc9cbf051c42d72353d4",
"assets/assets/js/package/olm.js": "e9f296441f78d7f67c416ba8519fe7ed",
"assets/assets/js/package/olm_legacy.js": "54770eb325f042f9cfca7d7a81f79141",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "ab9337574d85026108110bb29e3f1593",
"assets/fonts/Ubuntu/UbuntuMono-Regular.ttf": "c8ca9c5cab2861cf95fc328900e6f1a3",
"assets/fonts/Ubuntu/Ubuntu-Italic.ttf": "9f353a170ad1caeba1782d03dd8656b5",
"assets/fonts/Ubuntu/Ubuntu-Regular.ttf": "84ea7c5c9d2fa40c070ccb901046117d",
"assets/fonts/Ubuntu/Ubuntu-Bold.ttf": "896a60219f6157eab096825a0c9348a8",
"assets/fonts/Ubuntu/Ubuntu-BoldItalic.ttf": "c16e64c04752a33fc51b2b17df0fb495",
"assets/fonts/MaterialIcons-Regular.otf": "2369d2c45d078e02f4a9de2007e4b5aa",
"assets/fonts/Inconsolata/Inconsolata-Regular.ttf": "e264f34eef25b5af18c240ecfca2d67b",
"assets/fonts/Inconsolata/Inconsolata-Bold.ttf": "aa0f2ec17a4ba3e47bbc7ce533a93f50",
"assets/fonts/Inconsolata/Inconsolata-Light.ttf": "aff8f4d4930b9e50eae584d911c309a4",
"assets/FontManifest.json": "bb3cfdf2ea5c6c9196bb096a913a6bfa",
"assets/AssetManifest.bin.json": "877ab593c56a3a497b26fa83144afc49",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "6af29a309506697d8ab27e6ce59b7013",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "9f548f4965ec7e71b409ca4bf9ebb0b9",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3fcc569133fef05385aac13b534a1e9c",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "6ec08e501c87a225b5555290b69821ce",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/AssetManifest.json": "03609728d649a4a7f994cfe3734a61fd",
"main.dart.js_249.part.js": "197472ec62a7968d46e4a865ca9e74f6",
"main.dart.js_204.part.js": "361597cd68203369acc072353dabbbc0",
"main.dart.js_240.part.js": "967ad8998da94d54c89794f5aad508c4",
"version.json": "4466c949d5b888151792995161566f25",
"main.dart.js_233.part.js": "989f693668b2644cde35f7e4d39441d4",
"main.dart.js_223.part.js": "68a5cab0af93e4fd8ee1dd2975ef22f5",
"main.dart.js_193.part.js": "5047a6edd2dd1c4c7760d1c04139eee5",
"main.dart.js_168.part.js": "070a07c8514749c9d665087370ca37a0",
"main.dart.js_215.part.js": "5c9e2617bdc00db82476d6d0d3cbb84b",
"flutter.js": "4b2350e14c6650ba82871f60906437ea",
"main.dart.js_243.part.js": "d56c48778100ccf420b9c2f0b10adab7",
"main.dart.js_195.part.js": "db5fe4038b2b1ad316dfd4d14b3a9e1f",
"main.dart.js": "972be97576fd0928e34eb987707fe68f",
"main.dart.js_216.part.js": "dbf9aa40bca99cefa62eb9a39663968a",
"main.dart.js_2.part.js": "603b68b336f53340312f5012d6817c78",
"main.dart.js_244.part.js": "4b87fd39df083855c093330b08205ce2",
"main.dart.js_159.part.js": "a1e9c252e533428bfddc7575eb44f6d6",
"main.dart.js_205.part.js": "f8b7459da88ce7e2b1e9c269ff45275a",
"main.dart.js_17.part.js": "a2c6ee00f767c28b6afcca38bae86c98",
"main.dart.js_231.part.js": "781c13dff1c3aa19b3217882cc1ebfc9",
"main.dart.js_238.part.js": "a388df8a0f5db84b135a110756efb8ef",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_178.part.js": "2f6c5f0f257219cef2b883cea3fd49ea",
"main.dart.js_245.part.js": "524cca5ffd57b188c52f476823ef7580",
"main.dart.js_253.part.js": "82ce1fbf3eac5605c6cf7d1445246da3",
"main.dart.js_255.part.js": "13618fdab16b9e1cb6fa4761131f0dd8",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_237.part.js": "f430e7db410ec45245d9503b3ddb590a",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_206.part.js": "8a8896f2d06bdd8e20e5bd0df7b1d070",
"main.dart.js_200.part.js": "633f3eb10a9ef452f70bfddcdfee9853",
"main.dart.js_224.part.js": "7bd76f16d277d5266318da0f75457dc0",
"main.dart.js_192.part.js": "a459db14c2a793185433b9a4d8b86691",
"main.dart.js_257.part.js": "1b41648c83f6d1889e9af6cfddd83450",
"main.dart.js_211.part.js": "90662057b8a9d409f0309b0dd7cb2fca",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_169.part.js": "f052ebc18e3c694ea4cca440e65bb18c",
"main.dart.js_239.part.js": "0492b8b40e1f0310c5f6d90a62e2309c",
"main.dart.js_207.part.js": "5876599a3d94b91de4725e410f66a806",
"main.dart.js_191.part.js": "0e099bb781820a49715fc8014609782a",
"main.dart.js_217.part.js": "c0d6d799973c233a65bfdaf25b50828e",
"main.dart.js_242.part.js": "40972867c131271b8e15edde39b55cc7",
"main.dart.js_251.part.js": "709812b0129421142dcece62d31cfc76",
"main.dart.js_250.part.js": "dda0b7461abc34e6b9fc9f79a47652da",
"main.dart.js_235.part.js": "b3d2100f9821700a99c90304b9c76a77",
"main.dart.js_256.part.js": "03c15c2a014c615da307751c9c6619e1",
"main.dart.js_1.part.js": "26f7341d4e0748eb07d486fe64ed730c",
"flutter_bootstrap.js": "af8fc2768abb6c240bce02848b2fd9f6",
"main.dart.js_226.part.js": "c13df99d68d66e00e5935f7c7956d6cb"};
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
