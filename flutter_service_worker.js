'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"main.dart.js_207.part.js": "38494e3155e4e672a92b37eb5686565f",
"main.dart.js_239.part.js": "fad607f4c062648755451746a12d375e",
"main.dart.js_158.part.js": "ef599342a838713dd0db83fe70467b91",
"main.dart.js_193.part.js": "c0e16425545bcab718391c5f838482a3",
"main.dart.js_241.part.js": "d237950857619ee0b437a97cdf0eb2fc",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_246.part.js": "4f7223cd52df94bea4713226f1294f87",
"flutter_bootstrap.js": "d925a89bd922d23e274a874228bf036c",
"main.dart.js_205.part.js": "9d0a4244bc1e3325db1846de07330ef5",
"main.dart.js_220.part.js": "834c9bd363f87bee4941e5b3da5cd26c",
"main.dart.js_19.part.js": "9f5c51e941cba30165f0a275219868ef",
"main.dart.js_203.part.js": "9fa62633143303651586cf8a2683ac7e",
"main.dart.js_192.part.js": "06d4a7d7946d150289d933d1df36022d",
"main.dart.js_213.part.js": "db1bb4ec745071f83f05e2379392ae6f",
"main.dart.js_254.part.js": "98de2f7d1c8b2e6236c7ff7353f04145",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_169.part.js": "d87b88c6e98ee2ccb39a3137e4e80797",
"main.dart.js_232.part.js": "ca969c374bd4e80ecf596aeeb8b08671",
"main.dart.js_252.part.js": "a020fe10f71972e38b579c8ca052e5c8",
"main.dart.js_240.part.js": "36aac3473b3b25e1c26a5e4cd8a57416",
"main.dart.js_209.part.js": "dfa8ddb63063f6553eb71d42f3b68f61",
"main.dart.js_196.part.js": "62bf0572c54ac3975de69d1e75b99d8b",
"main.dart.js_218.part.js": "4cf7fe2e4bdb5263b6c23f3fd8cdad2b",
"main.dart.js_208.part.js": "e60900cf4ce2f01049ae33bb31a0ef7e",
"main.dart.js_237.part.js": "0a8c34cd10537130a6d18e0f2cce3cf3",
"main.dart.js_244.part.js": "4ba46aaa84c41748c350b1b793236df8",
"main.dart.js_225.part.js": "766895f482a09c87e7f768e967d6e27f",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_260.part.js": "daf00bae6ff309ffa87a084ba59afcde",
"main.dart.js_236.part.js": "1ace94e8c361e6eb01a4da464945b098",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_234.part.js": "f3f70675fe2dea5da816e81741657681",
"main.dart.js_214.part.js": "e150cf02c4869dccbf9a2105d813a5c4",
"main.dart.js_259.part.js": "3353cc5589e2e8575eb8b394ad0f469d",
"main.dart.js_186.part.js": "6132f444d8ec59875ae3be47c6bebbc9",
"main.dart.js_178.part.js": "25b99bd9928ec2aaa0ac1ac224d936a4",
"main.dart.js_243.part.js": "9a795603bd4ad6746a7466584826fdf7",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_258.part.js": "48e5daccffbc11dc6541566b4f11ac25",
"main.dart.js_170.part.js": "5f1e5e13fc2ddc99d3c42190d8c0de66",
"main.dart.js_210.part.js": "7b70993a59599c80c1e25b019a4959c2",
"main.dart.js_256.part.js": "c35112af49ae8c89d235eac92c3bbb87",
"main.dart.js_251.part.js": "19d2cc5f78cfd6b0f0f6875a2a93b988",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"main.dart.js_257.part.js": "d20a50962a89fb42586e1d64fda4fe18",
"main.dart.js_219.part.js": "468a8271860826494ed26ab10a96d189",
"main.dart.js_261.part.js": "18ce0b300f9e19a4843a955dc6ad4427",
"main.dart.js_1.part.js": "ba2d035457649eea034948ea6db05adb",
"main.dart.js_194.part.js": "0f8bc21233642c22e48cdf3d5f3f42a8",
"main.dart.js_171.part.js": "06a9152325b9ba61c6a481d0ff16bdb3",
"main.dart.js_184.part.js": "19563838491e9c44f6c69a22b7f67091",
"main.dart.js_226.part.js": "650eea209330c9378d75bc0cf9728d94",
"main.dart.js_255.part.js": "68f65696ea1266ddc39ccf4677ff2d44",
"main.dart.js_250.part.js": "4af7a3ea19604c36849aafb432043d9c",
"main.dart.js": "350ca2426ac8d529196e1f4e85d771ec",
"main.dart.js_245.part.js": "12aed3e488214ea17344563b29cd5f0a",
"main.dart.js_228.part.js": "ff4e571bdd53dc5b0ab3a2d9e3502c7e",
"index.html": "cb6cac85093df81e014215b01f8e09c4",
"/": "cb6cac85093df81e014215b01f8e09c4",
"main.dart.js_238.part.js": "3751b7aa43f3aba790fa7f11e8cae24e",
"main.dart.js_160.part.js": "c8e8eba6e7c8eff8a90a5b7990103150",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "7f759f00ff775c6dd13b26289c02d28f",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/FontManifest.json": "db8f453ee5bd623ef9ffbe9d7a009cf7",
"assets/NOTICES": "1e397ff2aaad1a91003e6288334bbba8",
"assets/AssetManifest.json": "7982f7b940bc5d289c2744e53a29f83d",
"assets/AssetManifest.bin": "2d9c9db994bfcebec6a125ba8d0fac63",
"assets/AssetManifest.bin.json": "1f4b9d7a9add599ed8d44f4e11c151b7",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/fonts/MaterialIcons-Regular.otf": "f9a926c5f327d19eaf218a189464249f",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "12f5bb4260049ea123aded62c5ea182e",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "d006f0519d22d963b538de78d8983292",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83"};
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
