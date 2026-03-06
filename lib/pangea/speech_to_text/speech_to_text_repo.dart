import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/pangea/speech_to_text/speech_to_text_response_model.dart';

class _SpeechToTextCacheItem {
  final Future<SpeechToTextResponseModel> data;
  final DateTime timestamp;

  const _SpeechToTextCacheItem({required this.data, required this.timestamp});
}

class SpeechToTextRepo {
  static final Map<String, _SpeechToTextCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<Result<SpeechToTextResponseModel>> get(
    String accessToken,
    SpeechToTextRequestModel request,
  ) {
    final cached = _getCached(request);
    if (cached != null) {
      return _getResult(request, cached);
    }

    final future = _fetch(accessToken, request);
    _setCached(request, future);
    return _getResult(request, future);
  }

  static Future<SpeechToTextResponseModel> _fetch(
    String accessToken,
    SpeechToTextRequestModel request,
  ) async {
    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.speechToText,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to translate text: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    return SpeechToTextResponseModel.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
  }

  static Future<Result<SpeechToTextResponseModel>> _getResult(
    SpeechToTextRequestModel request,
    Future<SpeechToTextResponseModel> future,
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

  static Future<SpeechToTextResponseModel>? _getCached(
    SpeechToTextRequestModel request,
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
    SpeechToTextRequestModel request,
    Future<SpeechToTextResponseModel> response,
  ) => _cache[request.hashCode.toString()] = _SpeechToTextCacheItem(
    data: response,
    timestamp: DateTime.now(),
  );
}
