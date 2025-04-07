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
"main.dart.js_210.part.js": "37c37bf250190900bc582ab2ca3bd907",
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
"main.dart.js_229.part.js": "c73647bf2b73fe9cb068a7bd011a1b04",
"main.dart.js_174.part.js": "6c9f09fc5907bd45d5067d541f7f9c14",
"main.dart.js_258.part.js": "15459e86aa4d3cc7f276c52dae4ca9f8",
"main.dart.js_254.part.js": "9e9b76eb93f0027cd9729b7404d6e268",
"main.dart.js_247.part.js": "40ac6b3bea2080631539fd2774d35fb2",
"main.dart.js_212.part.js": "f5318f821d6005b33915309a2e43b2ff",
"index.html": "e64a4ed345231840abde6d867cd395f1",
"/": "e64a4ed345231840abde6d867cd395f1",
"main.dart.js_246.part.js": "44684706c12007b5e4cbcb41f993df9d",
"main.dart.js_164.part.js": "b2491545f4296f67e1840ce47afb29c3",
"main.dart.js_221.part.js": "b12de2db386ac54c11fd76e4c0b7bf58",
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
"assets/fonts/MaterialIcons-Regular.otf": "7bded4e001b0eeaff29df47689416842",
"assets/fonts/Inconsolata/Inconsolata-Regular.ttf": "e264f34eef25b5af18c240ecfca2d67b",
"assets/fonts/Inconsolata/Inconsolata-Bold.ttf": "aa0f2ec17a4ba3e47bbc7ce533a93f50",
"assets/fonts/Inconsolata/Inconsolata-Light.ttf": "aff8f4d4930b9e50eae584d911c309a4",
"assets/FontManifest.json": "5bc35d3d4d49c93b8e418f7c7b8a18e1",
"assets/AssetManifest.bin.json": "71960e60345dfe9178f74b25e5b6c642",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "3cd5f92cd498faf3d89cbe1c10439791",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "ca1046efe3e79da7ad7e6eecf8ac0e1e",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "8fc3df68fe8446810e9b5083c6561cd6",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "6ec08e501c87a225b5555290b69821ce",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/AssetManifest.json": "1e2c1efcfbafe5e4a83c5a080a1a9e1f",
"main.dart.js_183.part.js": "e51c870e6bf605f20821f92cde802279",
"main.dart.js_249.part.js": "245b4a29aa0e6c5b2cccd4ccb6d4d38c",
"main.dart.js_260.part.js": "a81dfc4db3f9feaf30300ced03e50102",
"main.dart.js_240.part.js": "f7b19ec0083fc503cb2d0648eb4f3702",
"version.json": "a058ff9442fc3002414e5dd4b1d8dfd1",
"main.dart.js_215.part.js": "5af1c7bd341866c92744dcf31a10593e",
"flutter.js": "4b2350e14c6650ba82871f60906437ea",
"main.dart.js_243.part.js": "9e5637e6fafcc48140f2aae4fea1b8bf",
"main.dart.js_209.part.js": "1ed448cd64a7c4a772493d1e508f63a2",
"main.dart.js": "381ad0797c59800e13c2690be2df94bb",
"main.dart.js_216.part.js": "811a89ae4f43f4959d10a912521eae5d",
"main.dart.js_2.part.js": "039f944307337836b5974a52a4afadfb",
"main.dart.js_244.part.js": "fc5676b5f1aafa49264de4b2f2e43d72",
"main.dart.js_205.part.js": "bb3373fc14d4723c205ca0c116c70ffc",
"main.dart.js_197.part.js": "7f660d1b7b4ec6b08ae0e77a6f23e9b5",
"main.dart.js_231.part.js": "23d2ca3dbc068be2372c2ad2635866d2",
"main.dart.js_220.part.js": "dc0389128214ae1ab28387e8cdde7224",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_228.part.js": "7d2482bece8b6b8d1c549813ba7ed13c",
"main.dart.js_175.part.js": "0f767bb5e1f9aba78abb5a5d1f68f7be",
"main.dart.js_262.part.js": "fa6a8c85ac2749d57b136080af331078",
"main.dart.js_253.part.js": "ea0f5d6a99d60280cf6221fd3ccaaf65",
"main.dart.js_255.part.js": "e60100d2782106bf014562995ae72d43",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js_237.part.js": "4083e90af17bbaedcac27c71294dd139",
"main.dart.js_241.part.js": "0df67b968929daa2e188f64bc3585f5a",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_200.part.js": "0c5dc48f8cf5b853dfaa855b17283469",
"main.dart.js_196.part.js": "7ca0eb4fb1c94529a2f9133421daf4fa",
"main.dart.js_189.part.js": "053a9dd80b40362a4be0309f33336348",
"main.dart.js_198.part.js": "2d85a8b6e0f14b5197926a483f9ae6fd",
"main.dart.js_257.part.js": "44172e3b742c7c339299177c7475357a",
"main.dart.js_211.part.js": "fe7733c7e60e9233cacef6a5b68e9cec",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_173.part.js": "0d8d7769df4af03b75cd165ee421db1c",
"main.dart.js_239.part.js": "7cf7a27894e64e1bda8589fc8b857dfc",
"main.dart.js_207.part.js": "c798e6fab089e40f874c1fd2d2f9c25f",
"main.dart.js_222.part.js": "8f056450ce9549165cd973b799c00bc1",
"main.dart.js_162.part.js": "7d4b2735b8536520f9c43199aced6055",
"main.dart.js_242.part.js": "8a20167330222d0bf00e585964551acf",
"main.dart.js_18.part.js": "aa2ca7a54f6a919b8c11a7b6faf2a079",
"main.dart.js_235.part.js": "2420eab5700972b0f347fb9a9c81454b",
"main.dart.js_248.part.js": "1a356b3f6d210de9d179206c86e8b8bf",
"main.dart.js_259.part.js": "ef8a1d7df1fcde586e918ffeb675ed9c",
"main.dart.js_1.part.js": "f467c5c15422173bd603cd7396bc45a8",
"main.dart.js_261.part.js": "fc20e3ae056ac812bdd3d34ad6fec1ad",
"flutter_bootstrap.js": "e08ce47705208b1e1d1f457da4b29214"};
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
