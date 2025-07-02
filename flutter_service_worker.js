'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"main.dart.js_228.part.js": "f74d581e6fa604bd41491e61089fc17b",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"splash/img/dark-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/light-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/light-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/light-1x.png": "92fff8efa59621bf2b218b65a7f64014",
"splash/img/dark-4x.png": "ead87864be6b8f2f3efbb04acd30549d",
"splash/img/light-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/img/dark-2x.png": "ef4801be19d1bf6976fd9d25e0450d4f",
"splash/img/dark-3x.png": "16878fb08884c14b4d8971feec70a8b3",
"splash/style.css": "ffbfc8e81bf12699a69e56fed40c3d90",
"splash/splash.js": "c6a271349a0cd249bdb6d3c4d12f5dcf",
"main.dart.js_164.part.js": "7e247d1c24f3ca2131eb05c8e7733ee2",
"main.dart.js_182.part.js": "63880cd6e65b655b75ab02845fb3fcf1",
"main.dart.js_242.part.js": "4bc0f840e6df2992ab2c9e531d520ad4",
"main.dart.js_243.part.js": "60654805dc89a9d338b7825564119601",
"main.dart.js_175.part.js": "c1db37ab548a01e5e21cfca50ea627db",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_162.part.js": "f585e4e5d693e4b537158df68c15ebd9",
"main.dart.js_217.part.js": "d4bee6aa9fc3432ca9eadf72f5402148",
"main.dart.js_231.part.js": "0b6533c9007319a3a968299844aaa203",
"main.dart.js_190.part.js": "dcb069daa5d016ca25af6af4a4d19d1f",
"main.dart.js_259.part.js": "1dd067b61ff7c02d54f69f89133ecf81",
"main.dart.js_262.part.js": "77d42bb906576228e4a56cc172de782c",
"main.dart.js_223.part.js": "b8cea912381b9410442723c3e895e8a1",
"main.dart.js_254.part.js": "30e9ec6e4c40e21119db4cd9e373eec6",
"main.dart.js_19.part.js": "69cae3d3b6dcc26585691f44d9fc5e7b",
"main.dart.js_248.part.js": "f60894f19190e57549a02a0ce2992dd0",
"main.dart.js_263.part.js": "ad8ee62cd07eb1373be54f538300977c",
"main.dart.js_241.part.js": "998441da36f112271b66e59110ddf57f",
"main.dart.js_249.part.js": "7fbe6f2579933ab4fb7c42f1f61d60b8",
"main.dart.js": "ad6c92e092a2cf73c28d128272e0ce7e",
"main.dart.js_253.part.js": "c7ff04186c42d0f023b6129cc1b33c8d",
"main.dart.js_258.part.js": "02a887e8fbdd07b23db9ae8e18e373bf",
"main.dart.js_260.part.js": "2b7b7df92d9371dd22193760e43acf06",
"main.dart.js_198.part.js": "49e4d8998557d902d762031986382242",
"main.dart.js_216.part.js": "6ed1712e95eaefc272a65000e01c0315",
"main.dart.js_1.part.js": "3aea3ef8274956fca9df9ec6659e6256",
"main.dart.js_196.part.js": "352b2a1648b78fea13e91708552674e2",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_264.part.js": "49d8a402125a956b82a2a1a6dc8c8195",
"main.dart.js_213.part.js": "d277a82257b07743f08f77eaffcad0b7",
"main.dart.js_222.part.js": "668ff9f4c41f1abae205f0e3e44db15f",
"main.dart.js_239.part.js": "23626b15bbc5c7b9b64fb5354feee21b",
"main.dart.js_240.part.js": "27b9f6906dd0b330d0cf05cc9514a74d",
"index.html": "13e487281ca406013c3045df84dda354",
"/": "13e487281ca406013c3045df84dda354",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "3213922bc687a7b4be73436f84ebf61c",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/handy_window/assets/handy-window.css": "0434ee701235cf1c72458fd4ce022a64",
"assets/packages/handy_window/assets/handy-window-dark.css": "45fb3160206a5f74c0a9f1763c00c372",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/record_web/assets/js/record.worklet.js": "356bcfeddb8a625e3e2ba43ddf1cc13e",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/AssetManifest.bin.json": "86e580fac6e0e2f13d604c35b8152322",
"assets/AssetManifest.bin": "12dd895f5ba12cd429f55c1cbab069ec",
"assets/NOTICES": "45952d4d7b79e94d33976013e8cf002d",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/assets/js/package/olm.wasm": "239a014f3b39dc9cbf051c42d72353d4",
"assets/assets/js/package/olm.js": "e9f296441f78d7f67c416ba8519fe7ed",
"assets/assets/js/package/olm_legacy.js": "54770eb325f042f9cfca7d7a81f79141",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/sounds/click.mp3": "4d465388e5b6012bfca2ef65733a9e51",
"assets/assets/sounds/phone.ogg": "5c8fb947eb92ca55229cb6bbf533c40f",
"assets/assets/sounds/call.ogg": "7e8c646f83fba83bfb9084dc1bfec31e",
"assets/assets/sounds/notification.ogg": "d928d619828e6dbccf6e9e40f1c99d83",
"assets/assets/sounds/WoodenBeaver_stereo_message-new-instant.ogg": "88fb9823caeb64edffd343530fae9e8b",
"assets/assets/banner_transparent.png": "364e2030f739bf0c7ed1c061c4cb5901",
"assets/assets/pangea/Avatar_4.png": "2f9397700c5f6d7d1d4ccc7c3de1eed5",
"assets/assets/pangea/logo.png": "b43f03f8ba56de7226362a15fb3f762d",
"assets/assets/pangea/PangeaChat_Glow_Logo.png": "d05cd7ec95208479d61bac9de8a25383",
"assets/assets/pangea/Avatar_5.png": "85d39fdfb0e0c22ad31a3eba16eddaaf",
"assets/assets/pangea/Avatar_2.png": "a60b04b8f2e3b6187a39e7ead45b876a",
"assets/assets/pangea/apple.svg": "c0ab9806f89b13b542a1438b1226ef9d",
"assets/assets/pangea/bot_faces/addled.png": "7a8daa6873d3b53890863275b55e4011",
"assets/assets/pangea/bot_faces/surprised.png": "2a7351fe2b7b6d64b63bc7d6f7160677",
"assets/assets/pangea/bot_faces/pangea_bot.riv": "c68676f3009c2f0e66388f2377a6c491",
"assets/assets/pangea/bot_faces/right.png": "80012f010e49e293e4ddb4aa9edc5b16",
"assets/assets/pangea/bot_faces/shocked.png": "1110398010407ece6e8d221dc9ad1831",
"assets/assets/pangea/bot_faces/left.png": "16235bc7d7f423ac351c1d98ee9a69c5",
"assets/assets/pangea/bot_faces/down.png": "f54059b94b20848cb653663368f9567d",
"assets/assets/pangea/Avatar_3.png": "913618723d7fc57512335fa0ed347704",
"assets/assets/pangea/pangea_logo.svg": "0104ecf95f749a4e0d4ac1154c5bb097",
"assets/assets/pangea/Avatar_1.png": "69a9cc8b0ea1f99c2fefc5930141c0ba",
"assets/assets/pangea/google.svg": "6d16705367d9de665135bff410f6ff7b",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/logo.svg": "d042b70cf11a41f2764028e85b07a00a",
"assets/assets/banner.png": "4a005db27a8787aea061537223dabb7d",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/AssetManifest.json": "3aa461c888442e3624f7f5159da65eec",
"assets/fonts/Inconsolata/Inconsolata-Regular.ttf": "e264f34eef25b5af18c240ecfca2d67b",
"assets/fonts/Inconsolata/Inconsolata-Bold.ttf": "aa0f2ec17a4ba3e47bbc7ce533a93f50",
"assets/fonts/Inconsolata/Inconsolata-Light.ttf": "aff8f4d4930b9e50eae584d911c309a4",
"assets/fonts/MaterialIcons-Regular.otf": "d244985bab87a6ef2ea6af595b8b88cc",
"assets/FontManifest.json": "df1162f2a0e446993d9403d9d817ed3c",
"main.dart.js_200.part.js": "2df8d479723233fcf9d53c454dfcb6ac",
"main.dart.js_197.part.js": "fef5d5543625ea5c242edb4e46fca924",
"main.dart.js_211.part.js": "ee01c7fb798ff0452a7b6e595aff51d6",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_188.part.js": "a7cf63947ccc7a571849f42f3e7ab149",
"main.dart.js_229.part.js": "c8cee3a7985cdb4225eb0a042193ec4a",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"main.dart.js_246.part.js": "e332c1367a7f78a7bcce3dc1db850882",
"main.dart.js_173.part.js": "5b3cd7e89dd2bb4c47e144ed8786f35d",
"main.dart.js_244.part.js": "4acfde554a29ee5ea506c59176c74cea",
"main.dart.js_261.part.js": "ee23745ced00ec0a7723e15ce538efd8",
"main.dart.js_208.part.js": "9335f4b9c43f39fa8a3e53fed63431a6",
"main.dart.js_255.part.js": "0c1ea0264a13693fd5781ccdc5c2ed15",
"flutter_bootstrap.js": "04db2f77911c154c7ce2b5bc5d3c7743",
"main.dart.js_210.part.js": "bf83ae0162541259103e6343fcf671de",
"main.dart.js_174.part.js": "be756551c8e819ae1b4e25e6a476ee7c",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"main.dart.js_212.part.js": "2dcebafbf8452a8d4e2d0736819cbc79",
"main.dart.js_221.part.js": "7d934bb7b852a877d5edc8a4c9c629d4",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_247.part.js": "6ef8f9c4061f72094ff605fc672108d5",
"main.dart.js_237.part.js": "24f47436d53b5b45609d869ebe849c5b",
"main.dart.js_257.part.js": "a1a6a0d339b32fcb2f88ef98e5924088",
"main.dart.js_206.part.js": "45a68a3d5ceb6ae3c8cb93ba52e9b294",
"main.dart.js_235.part.js": "233163cc3958a7d3e7864506e53f864c"};
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
