'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_257.part.js": "654cd846ed92201037bf9010f9cb9e58",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"main.dart.js_233.part.js": "95c12d80b45142672aa161af12de8b8e",
"main.dart.js_168.part.js": "fc481a76d7ebd50665b809c0357d3532",
"main.dart.js_208.part.js": "610727ba3073c8821f27415d8aecb46a",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_237.part.js": "b1b66b3e6b41452ae72a83d66e0848d4",
"main.dart.js_240.part.js": "c9437685778e96e5f553a68c1ab40dfa",
"main.dart.js_231.part.js": "045d54fb1c8ffeb24d7447ee45d6bb1a",
"main.dart.js_202.part.js": "629c282bfc196e9f5f60b87265627564",
"main.dart.js_158.part.js": "299d449a54416cf23dc0d0e9bbe73867",
"main.dart.js_259.part.js": "b8162e091a1c118cd30bc53c11a25ebb",
"main.dart.js_238.part.js": "d46cb78e7af2731a158679f982d02fc8",
"main.dart.js_212.part.js": "88dd18fafaf5b048d2bd86e1bf5a66c4",
"main.dart.js_182.part.js": "0b1e7c263c355133d16e2c4c6ef89e27",
"main.dart.js_209.part.js": "0e57eaa2e7d1b2b05deea72c871d7a57",
"main.dart.js_192.part.js": "98b84d3caa48667e3610462b182cae83",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_253.part.js": "398e7c18a86e2eff393d6d998eecc8be",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_254.part.js": "9f95029717e2d2601986cc28b94be8c2",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"main.dart.js": "4232b8f043f8ccabe643145d8a140cbb",
"main.dart.js_204.part.js": "65f8e3c0967a5f827032938b3287951c",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_1.part.js": "7f1a10798b369e6ff246ecb93d06dbb9",
"main.dart.js_235.part.js": "5581c7f4aded2a885e7a8ee5289fb77d",
"main.dart.js_249.part.js": "2cea42ba9de1fa12bd422dccc924bd16",
"main.dart.js_169.part.js": "3254cc13da6d73b884a42caacdd0df18",
"main.dart.js_18.part.js": "feffb69e3457053a44101425bde2e040",
"main.dart.js_213.part.js": "5df862b5ae92401563a0a2a4139ddbee",
"assets/NOTICES": "1e397ff2aaad1a91003e6288334bbba8",
"assets/fonts/MaterialIcons-Regular.otf": "ed1f9936f28855192b59622a917ae33f",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
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
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "968caf2040e4ce7eddbfba1e8a5cfc8b",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "115f3f226f3839ef5f76008bb9531150",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"assets/AssetManifest.bin.json": "1f4b9d7a9add599ed8d44f4e11c151b7",
"assets/AssetManifest.bin": "2d9c9db994bfcebec6a125ba8d0fac63",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "d576b4ab8e8e9707baf8d411c260499a",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"flutter_bootstrap.js": "a8b223062d35f01e5b510d04fc7bb43a",
"main.dart.js_242.part.js": "dc6a61c77196b70ac1fda13a383da880",
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
"main.dart.js_260.part.js": "1d2445854cff89fc2b0cb22213a35076",
"main.dart.js_156.part.js": "bd35dac902e9ee493a646411bae1f1f9",
"main.dart.js_244.part.js": "d2fdad663e08ea52a8be11ca906ded37",
"main.dart.js_191.part.js": "ebd76068140908efb633d42dabd9344e",
"main.dart.js_219.part.js": "a1a0aeb232b66d2257a44d1897839d18",
"main.dart.js_184.part.js": "afe73637c3db582aa87c929e5c1bed17",
"main.dart.js_217.part.js": "4ba859d408e265648d73706b6683c20c",
"main.dart.js_256.part.js": "3aff18d133ca766f3e4de70b5fee3b52",
"main.dart.js_218.part.js": "6e595d88035500c63d355c4bbd39ffd5",
"main.dart.js_255.part.js": "d8ecf7cfc974268976b1366a771b096d",
"main.dart.js_250.part.js": "48f0f4a77976bcfd84859b9f915def4d",
"main.dart.js_239.part.js": "ca820f6c8d9cec3032771ca9dece2f27",
"main.dart.js_176.part.js": "aa8483a9c008a8cb9fd43c3a4a4cdd13",
"main.dart.js_167.part.js": "78cc1f126551643475eee6702fc7d993",
"main.dart.js_251.part.js": "0223e532041d1078f71512cd85c0e359",
"main.dart.js_224.part.js": "fb80c54c1b733c87018978473cdd9fbc",
"main.dart.js_236.part.js": "0ae8e35b8a1ba5c9e22027b8aa7f236e",
"main.dart.js_243.part.js": "83337362d65d5ebfbd991d742d26037c",
"main.dart.js_245.part.js": "1df587cbe9ae0e0b36fa5b2901042646",
"main.dart.js_194.part.js": "3942d29e64c88277caab58118494b924",
"main.dart.js_227.part.js": "967930cf0ad7bcfc1ee569be58d1d559",
"main.dart.js_207.part.js": "5e774f8b090dce8ff04768b96cc0bac1",
"main.dart.js_258.part.js": "7bf0aa86b7fb6ff307f104e53390b964",
"main.dart.js_206.part.js": "c24d2bc7d4ee88c858e17dfdc7dbfdfc",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"index.html": "1efdbab22b8cadcfea6daba492f0e198",
"/": "1efdbab22b8cadcfea6daba492f0e198",
"main.dart.js_225.part.js": "25bcb9702bb37e3ea37ce86f965b1cd5",
"main.dart.js_190.part.js": "038b6eef06dd0ffd01a6e511b4bed7cf"};
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
