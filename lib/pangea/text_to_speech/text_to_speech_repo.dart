import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/text_to_speech/text_to_speech_request_model.dart';
import 'package:fluffychat/pangea/text_to_speech/text_to_speech_response_model.dart';

class _TextToSpeechCacheItem {
  final Future<TextToSpeechResponseModel> data;
  final DateTime timestamp;

  const _TextToSpeechCacheItem({
    required this.data,
    required this.timestamp,
  });
}

class TextToSpeechRepo {
  static final Map<String, _TextToSpeechCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<Result<TextToSpeechResponseModel>> get(
    String accessToken,
    TextToSpeechRequestModel request,
  ) {
    final cached = _getCached(request);
    if (cached != null) {
      return _getResult(request, cached);
    }

    final future = _fetch(accessToken, request);
    _setCached(request, future);
    return _getResult(request, future);
  }

  static Future<TextToSpeechResponseModel> _fetch(
    String accessToken,
    TextToSpeechRequestModel request,
  ) async {
    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.textToSpeech,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to convert text to speech: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    return TextToSpeechResponseModel.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
  }

  static Future<Result<TextToSpeechResponseModel>> _getResult(
    TextToSpeechRequestModel request,
    Future<TextToSpeechResponseModel> future,
  ) async {
    try {
      final res = await future;
      return Result.value(res);
    } catch (e, s) {
      _cache.remove(request.hashCode.toString());
      ErrorHandler.logError(
        e: e,
        s: s,
        data: request.toJson(),
      );
      return Result.error(e);
    }
  }

  static Future<TextToSpeechResponseModel>? _getCached(
    TextToSpeechRequestModel request,
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
    TextToSpeechRequestModel request,
    Future<TextToSpeechResponseModel> response,
  ) =>
      _cache[request.hashCode.toString()] = _TextToSpeechCacheItem(
        data: response,
        timestamp: DateTime.now(),
      );
}
