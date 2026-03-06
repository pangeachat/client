import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/repo/language_detection_request.dart';
import 'package:fluffychat/pangea/events/repo/language_detection_response.dart';

class _LanguageDetectionCacheItem {
  final Future<LanguageDetectionResponse> data;
  final DateTime timestamp;

  const _LanguageDetectionCacheItem({
    required this.data,
    required this.timestamp,
  });
}

class LanguageDetectionRepo {
  static final Map<String, _LanguageDetectionCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<Result<LanguageDetectionResponse>> get(
    String accessToken,
    LanguageDetectionRequest request,
  ) {
    final cached = _getCached(request);
    if (cached != null) {
      return _getResult(request, cached);
    }

    final future = _fetch(accessToken, request);
    _setCached(request, future);
    return _getResult(request, future);
  }

  static Future<LanguageDetectionResponse> _fetch(
    String accessToken,
    LanguageDetectionRequest request,
  ) async {
    final Requests req = Requests(
      accessToken: accessToken,
      choreoApiKey: Environment.choreoApiKey,
    );
    final Response res = await req.post(
      url: PApiUrls.languageDetection,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to detect language: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    return LanguageDetectionResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
  }

  static Future<Result<LanguageDetectionResponse>> _getResult(
    LanguageDetectionRequest request,
    Future<LanguageDetectionResponse> future,
  ) async {
    try {
      final res = await future;
      return Result.value(res);
    } catch (e, s) {
      _cache.remove(request.hashCode.toString());
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }

  static Future<LanguageDetectionResponse>? _getCached(
    LanguageDetectionRequest request,
  ) {
    final cacheKeys = [..._cache.keys];
    for (final key in cacheKeys) {
      if (DateTime.now().difference(_cache[key]!.timestamp) >= _cacheDuration) {
        _cache.remove(key);
      }
    }

    return _cache[request.hashCode.toString()]?.data;
  }

  static void _setCached(
    LanguageDetectionRequest request,
    Future<LanguageDetectionResponse> response,
  ) => _cache[request.hashCode.toString()] = _LanguageDetectionCacheItem(
    data: response,
    timestamp: DateTime.now(),
  );
}
