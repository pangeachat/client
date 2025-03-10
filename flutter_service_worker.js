'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"canvaskit/skwasm.js": "ac0f73826b925320a1e9b0d3fd7da61c",
"canvaskit/skwasm.wasm": "828c26a0b1cc8eb1adacbdd0c5e8bcfa",
"canvaskit/skwasm.js.symbols": "96263e00e3c9bd9cd878ead867c04f3c",
"canvaskit/skwasm.worker.js": "89990e8c92bcb123999aa81f7e203b1c",
"canvaskit/canvaskit.wasm": "e7602c687313cfac5f495c5eac2fb324",
"canvaskit/canvaskit.js": "26eef3024dbc64886b7f48e1b6fb05cf",
"canvaskit/canvaskit.js.symbols": "efc2cd87d1ff6c586b7d4c7083063a40",
"canvaskit/chromium/canvaskit.wasm": "ea5ab288728f7200f398f60089048b48",
"canvaskit/chromium/canvaskit.js": "b7ba6d908089f706772b2007c37e6da4",
"canvaskit/chromium/canvaskit.js.symbols": "e115ddcfad5f5b98a90e389433606502",
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
"main.dart.js_174.part.js": "b529418b24d5b750362a4ab1454e9fea",
"main.dart.js_176.part.js": "6d0730cdc58ccb3222ff9c8db52ec607",
"main.dart.js_212.part.js": "a976702a901a4ade4b74caf18fe3148b",
"main.dart.js_184.part.js": "0311e7d9e9c97d1dce4fb83a3e669a30",
"index.html": "0227725926492fb3ac89c7d258afa181",
"/": "0227725926492fb3ac89c7d258afa181",
"main.dart.js_246.part.js": "e5e2a825bc79b6eda0b1ce49c70626a1",
"main.dart.js_190.part.js": "6ddc6b16c91b8464a615b18bcaa08ea3",
"assets/NOTICES": "bd69ac967f33447d31e7564471422edc",
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
"assets/AssetManifest.bin": "7aed6a3108fc12afc512b5c2e4b1d929",
"assets/fonts/Ubuntu/UbuntuMono-Regular.ttf": "c8ca9c5cab2861cf95fc328900e6f1a3",
"assets/fonts/Ubuntu/Ubuntu-Italic.ttf": "9f353a170ad1caeba1782d03dd8656b5",
"assets/fonts/Ubuntu/Ubuntu-Regular.ttf": "84ea7c5c9d2fa40c070ccb901046117d",
"assets/fonts/Ubuntu/Ubuntu-Medium.ttf": "d3c3b35e6d478ed149f02fad880dd359",
"assets/fonts/Ubuntu/Ubuntu-Bold.ttf": "896a60219f6157eab096825a0c9348a8",
"assets/fonts/Ubuntu/Ubuntu-BoldItalic.ttf": "c16e64c04752a33fc51b2b17df0fb495",
"assets/fonts/MaterialIcons-Regular.otf": "2855807da5ba308ae036bbea87824fa6",
"assets/fonts/Inconsolata/Inconsolata-Regular.ttf": "e264f34eef25b5af18c240ecfca2d67b",
"assets/fonts/Inconsolata/Inconsolata-Bold.ttf": "aa0f2ec17a4ba3e47bbc7ce533a93f50",
"assets/fonts/Inconsolata/Inconsolata-Light.ttf": "aff8f4d4930b9e50eae584d911c309a4",
"assets/FontManifest.json": "5bc35d3d4d49c93b8e418f7c7b8a18e1",
"assets/AssetManifest.bin.json": "71960e60345dfe9178f74b25e5b6c642",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "4c3919f98b201d17b053b368b2a7ae1d",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "ca1046efe3e79da7ad7e6eecf8ac0e1e",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "8fc3df68fe8446810e9b5083c6561cd6",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "6ec08e501c87a225b5555290b69821ce",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/AssetManifest.json": "1e2c1efcfbafe5e4a83c5a080a1a9e1f",
"main.dart.js_214.part.js": "5115e4f8eb5b4c5e8724bbe04c5afcf2",
"main.dart.js_213.part.js": "080bff8efaf8ecd85a38b9653461ffa0",
"main.dart.js_249.part.js": "bb8586046e526dce31f9f9d6605aa551",
"main.dart.js_260.part.js": "04074162c1610e41067555f3fbcc7a5c",
"version.json": "a058ff9442fc3002414e5dd4b1d8dfd1",
"main.dart.js_263.part.js": "3cb42ec0103191a2cbc5cb528acd6250",
"main.dart.js_233.part.js": "42320065f038f64d76b14aac9b37975a",
"main.dart.js_223.part.js": "76d53307007c77baf5564c1843c5e669",
"main.dart.js_264.part.js": "dbe300055459fd49d047644decbdbd28",
"flutter.js": "4b2350e14c6650ba82871f60906437ea",
"main.dart.js_243.part.js": "05f46cf5f6765a9ad6d5254d1e40d6d4",
"main.dart.js_209.part.js": "7159cf27ab34e1e703cf070accc13051",
"main.dart.js": "2abf91dd0f81dec5fa1628b9a51469c2",
"main.dart.js_2.part.js": "039f944307337836b5974a52a4afadfb",
"main.dart.js_244.part.js": "ad0e5f12aa69189a4d530344c9bc4d86",
"main.dart.js_165.part.js": "7a557bdcef64d0564d7d845ad5e7a837",
"main.dart.js_163.part.js": "3448d3eed70329ec9ab68dab5de87cb6",
"main.dart.js_197.part.js": "7b05f9cb8ef77986b5207324cd305475",
"main.dart.js_231.part.js": "ebfd6a49fce3348fb2bbb5695a0e46b8",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_175.part.js": "9e8285f1ba183d79169b2f36048b0157",
"main.dart.js_262.part.js": "0ad4dd971dd12855a504204a7bf192bb",
"main.dart.js_245.part.js": "9f2def599c1423dbca6f9ee855a024a6",
"main.dart.js_255.part.js": "4c2f36ed0095e736c7d6c6ec6b56f23a",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_237.part.js": "60f8dee941286e2079dd4c6365691f36",
"main.dart.js_241.part.js": "6d72ae10b87f3e1cebee542ab6c0d2d2",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_198.part.js": "2bad5c5d7f627571c3627b415693d68d",
"main.dart.js_224.part.js": "d66961bc011b4631378013db31f438f5",
"main.dart.js_257.part.js": "efd6eeed49e1b3a28fc8bf69e8edc596",
"main.dart.js_211.part.js": "6204be4812c8aac1f6cc204c50f6e32f",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_239.part.js": "3fc9cf8f24a22d187c2bcfc37cffc434",
"main.dart.js_199.part.js": "316a4c15d20d42cdfc8eced952acf6bf",
"main.dart.js_207.part.js": "890df86b05d7936c4b3fbe0e8f7ebd1f",
"main.dart.js_222.part.js": "a544978686b671f257bcac371df8b769",
"main.dart.js_218.part.js": "7175fc37501af6246a6a24e1c498ebab",
"main.dart.js_217.part.js": "897140930ebc117e2cb5cba0b1f04455",
"main.dart.js_242.part.js": "8355deccce6d2fcc37a412cc733424b9",
"main.dart.js_251.part.js": "16783bb3036ca57aacae60633c50bd14",
"main.dart.js_18.part.js": "e6f1bd535afb8e6f6cf3f153f560f70c",
"main.dart.js_250.part.js": "e03f27e093272585c555665e57cd8063",
"main.dart.js_230.part.js": "acc85b2ac45853165a5a012ea2848e53",
"main.dart.js_248.part.js": "98592883ea3cba0886844f88fb606156",
"main.dart.js_259.part.js": "d21e1ae3ab0d9f5d894010b94889839d",
"main.dart.js_256.part.js": "e17d11d463f38c92825160d16ee57251",
"main.dart.js_201.part.js": "c014e68d70b8a0aa814352c45757b6ec",
"main.dart.js_1.part.js": "eb749358d5e266a3a8507d43d41ef250",
"main.dart.js_261.part.js": "f38a2bddb402ec52263f3a722ae5179b",
"flutter_bootstrap.js": "c0a3914d76a78f2b6bab7f2db066ac83"};
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
