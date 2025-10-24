//Question for Jordan - is this for an individual token or could it be a span?

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';

import 'package:fluffychat/pangea/choreographer/repo/full_text_translation_request_model.dart';
import 'package:fluffychat/pangea/choreographer/repo/full_text_translation_response_model.dart';
import '../../common/config/environment.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';

class FullTextTranslationRepo {
  static final Map<String, FullTextTranslationResponseModel> _cache = {};
  static Timer? _cacheTimer;

  // start a timer to clear the cache
  static void startCacheTimer() {
    _cacheTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      clearCache();
    });
  }

  // stop the cache time (optional)
  static void stopCacheTimer() {
    _cacheTimer?.cancel();
  }

  // method to clear the cache
  static void clearCache() {
    _cache.clear();
  }

  static String _generateCacheKey({
    required String text,
    required String srcLang,
    required String tgtLang,
    required int offset,
    required int length,
    bool? deepL,
  }) {
    return '${text.hashCode}-$srcLang-$tgtLang-$deepL-$offset-$length';
  }

  static Future<FullTextTranslationResponseModel> translate({
    required String accessToken,
    required FullTextTranslationRequestModel request,
  }) async {
    // start cache timer when the first API call is made
    startCacheTimer();

    final cacheKey = _generateCacheKey(
      text: request.text,
      srcLang: request.srcLang ?? '',
      tgtLang: request.tgtLang,
      offset: request.offset ?? 0,
      length: request.length ?? 0,
      deepL: request.deepL,
    );

    // check cache first
    if (_cache.containsKey(cacheKey)) {
      if (_cache[cacheKey] == null) {
        _cache.remove(cacheKey);
      } else {
        return _cache[cacheKey]!;
      }
    }

    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.simpleTranslation,
      body: request.toJson(),
    );

    final responseModel = FullTextTranslationResponseModel.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );

    // store response in cache
    _cache[cacheKey] = responseModel;

    return responseModel;
  }
}
