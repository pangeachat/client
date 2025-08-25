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
"main.dart.js_204.part.js": "6155d728896e9c9c132f64e2c93366f0",
"main.dart.js_207.part.js": "a06af5049d08c97c60c5be73d01bdeed",
"main.dart.js_242.part.js": "a9c802c43ac2e968c071233ce1d66b73",
"main.dart.js_216.part.js": "521360bfee60931eef3ce66c2bc217b2",
"main.dart.js_183.part.js": "12bb0ac1e3d35e921d2f377d6e2ccc46",
"main.dart.js_190.part.js": "f39509b7abc3f8acaf77310d0fd4659a",
"main.dart.js_193.part.js": "7e7d04da64193d1609ee9e505b039289",
"main.dart.js_241.part.js": "e2a9347d3f4b88697855f66874345202",
"main.dart.js_155.part.js": "2f385235e8c7408e8c4c54283b7efeca",
"main.dart.js_223.part.js": "0f8e53cbc668fbf245772c92793b71b7",
"auth.html": "88530dca48290678d3ce28a34fc66cbd",
"main.dart.js_191.part.js": "cd94a8b45d926bfa775ee612be16898d",
"main.dart.js_18.part.js": "cdf4eeb03e22c548fe0dece16edcecd9",
"main.dart.js_166.part.js": "5c3c25bd6af06ba8b509b040c5e2a531",
"flutter_bootstrap.js": "90efcd25e313877199055047923c0d27",
"main.dart.js_175.part.js": "b9c3cc923e68987c5e238435287c1c91",
"main.dart.js_205.part.js": "ee081c6449ca8c35fa416659fe6da720",
"main.dart.js_211.part.js": "549d0eca1e2185a3c18a4b1abc8e6386",
"main.dart.js_254.part.js": "cad87b7108dad159e7b19d01d2316623",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"main.dart.js_252.part.js": "0a04fc7eddf0daaccf6f88d66df019d0",
"main.dart.js_240.part.js": "2c29b797627a7f5cc33da04a70cc62ca",
"main.dart.js_167.part.js": "5ab7882cae2778e705a3ae01deef55f3",
"main.dart.js_237.part.js": "b7652950e92d4a306341cbb573284bc0",
"main.dart.js_225.part.js": "f25b64772e00f1497301eb6ce8dca452",
"favicon.png": "37d87985849bc680fe47a9330c3ea67e",
"main.dart.js_168.part.js": "01af1f2c33d57e3db91657ed325df8c9",
"main.dart.js_236.part.js": "df735c89d86eddc947d029e6efc4658b",
"icons/Icon-512.png": "85a29bc30ba39470883196b434b0c498",
"icons/Icon-192.png": "4e4ee2e9ac44d6d501f26380a60f40ed",
"manifest.json": "cc4b6aa791018840b65fd0b0e325b201",
"main.dart.js_202.part.js": "7adb1ec70ca71a564a53cef8055deb70",
"main.dart.js_229.part.js": "175b3a04488660d0de2c03b1b67c4e68",
"main.dart.js_234.part.js": "50976790955a1c93deb2fc370581b2ac",
"main.dart.js_231.part.js": "1f38554a809d8b67b4b020fe63517354",
"main.dart.js_206.part.js": "6e973a71987697528d60887f8b1c9312",
"main.dart.js_217.part.js": "c81c590214693f4951f64a5eb4a4663b",
"main.dart.js_243.part.js": "fc9cc6e6fea7a5dd5532eb9e5fed1086",
"main.dart.js_2.part.js": "37d62d65ea204401fa66da19b3c5a54d",
"version.json": "2b9e18a27963c905325bc945c6fb583c",
"main.dart.js_247.part.js": "5a4d2e7042b2874d85ccb6be9d646beb",
"main.dart.js_200.part.js": "bc82c1e10a7c03eb26bf2e1326e378a9",
"main.dart.js_235.part.js": "0466e19b0736ef0f4b0dd92923022d2b",
"main.dart.js_258.part.js": "5a4cd4abf7dcc62754d87f17082bc929",
"main.dart.js_210.part.js": "cdbc8aa9a48744b0f2290b52726aee6d",
"main.dart.js_256.part.js": "a3b68c66c96a01b015048d3864a8f93a",
"main.dart.js_249.part.js": "4828ab994ecd917bfe741d651caea7c2",
"main.dart.js_251.part.js": "decb59359f9617c3447b77565e145337",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"main.dart.js_257.part.js": "c5db33923ec5f9af877507593d2d5b14",
"main.dart.js_1.part.js": "b92ccd7a95e41710db93a907ed1cd5f4",
"main.dart.js_215.part.js": "fdc560d2eedd25a6fd667219434c7fb9",
"main.dart.js_189.part.js": "1a6b383a6c62a47dc53563e3fc2def7f",
"main.dart.js_255.part.js": "57c7a0775499e27319d82d5f13953a0c",
"main.dart.js": "ec61ede4920a50e26bd78d98f80edf95",
"main.dart.js_253.part.js": "d3ad3044314015a3401cba915c966764",
"main.dart.js_181.part.js": "2ee2092ea76aa9464d85b821787ada3c",
"main.dart.js_233.part.js": "e7d74a9297aece6fbc2c42ae33f0ad33",
"main.dart.js_248.part.js": "f21ff69ad2a49f89de6f05004b709f24",
"main.dart.js_222.part.js": "2c6abe31be36e52a204d54ad72ebca6a",
"main.dart.js_157.part.js": "07edcc0316d0229cb7160035e92b5d2a",
"index.html": "f91a85774c6f9a9d9169c64f6f55a465",
"/": "f91a85774c6f9a9d9169c64f6f55a465",
"main.dart.js_238.part.js": "e7c1ce5bc9e334401158e02a26948ac9",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "cc3a8a79a480f52dad3259ef7a81f9f7",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf": "fe2778759202af0a9f61f35a067da34b",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf": "3ec23c2e1c821134f8ee88ef6df5eb72",
"assets/packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf": "d576b4ab8e8e9707baf8d411c260499a",
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
"assets/fonts/MaterialIcons-Regular.otf": "0a0a17550689428c671cecb57edf00d0",
"assets/assets/info-logo.png": "9d1d72596564e6639fd984fea2dfd048",
"assets/assets/login_wallpaper.png": "26cbc6c27b3939434fbed6564bd2b169",
"assets/assets/encryption.png": "85367d8a3630d5791124f10a63e7f9d1",
"assets/assets/start_chat.png": "5f236310a0ac655505862b9d6a11056a",
"assets/assets/favicon.png": "3ea6cdc2aeab08defd0659bad734a69b",
"assets/assets/sas-emoji.json": "b9d99fc6dda6a3250af57af969b4a02d",
"assets/assets/colors.png": "fde0db0023d9fc4b7c96a8114e9329bb",
"assets/assets/logo.png": "d329be9cd7af685717f68e03561f96c0",
"assets/assets/logo_transparent.png": "f00cda39300c9885a7c9ae52a65babbf",
"assets/assets/vodozemac/vodozemac_bindings_dart.js": "0541f0a8e78891331ae4a8c081f9405c",
"assets/assets/vodozemac/vodozemac_bindings_dart_bg.wasm": "02af1197210d6cd13015c918a1274794",
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
