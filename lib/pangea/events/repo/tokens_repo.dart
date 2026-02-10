import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/repo/token_api_models.dart';

class _TokensCacheItem {
  final Future<TokensResponseModel> data;
  final DateTime timestamp;

  const _TokensCacheItem({required this.data, required this.timestamp});
}

class TokensRepo {
  static final Map<String, _TokensCacheItem> _tokensCache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<Result<TokensResponseModel>> get(
    String? accessToken,
    TokensRequestModel request,
  ) {
    final cached = _getCached(request);
    if (cached != null) {
      return _getResult(request, cached);
    }

    final future = _fetch(accessToken, request: request);
    _setCached(request, future);
    return _getResult(request, future);
  }

  static Future<TokensResponseModel> _fetch(
    String? accessToken, {
    required TokensRequestModel request,
  }) async {
    final Requests req = Requests(
      accessToken: accessToken,
      choreoApiKey: Environment.choreoApiKey,
    );
    final Response res = await req.post(
      url: PApiUrls.tokenize,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to fetch Tokens data: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    final Map<String, dynamic> json = jsonDecode(
      utf8.decode(res.bodyBytes).toString(),
    );

    final tokens = TokensResponseModel.fromJson(json);
    if (tokens.tokens.any((t) => t.pos == 'other')) {
      ErrorHandler.logError(
        e: Exception('Received token with pos "other"'),
        data: {"request": request.toJson(), "response": json},
        level: SentryLevel.warning,
      );
    }
    return tokens;
  }

  static Future<Result<TokensResponseModel>> _getResult(
    TokensRequestModel request,
    Future<TokensResponseModel> future,
  ) async {
    try {
      final res = await future;
      return Result.value(res);
    } catch (e, s) {
      _tokensCache.remove(request.hashCode.toString());
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }

  static Future<TokensResponseModel>? _getCached(TokensRequestModel request) {
    final cacheKeys = [..._tokensCache.keys];
    for (final key in cacheKeys) {
      if (_tokensCache[key]!.timestamp.isBefore(
        DateTime.now().subtract(_cacheDuration),
      )) {
        _tokensCache.remove(key);
      }
    }

    return _tokensCache[request.hashCode.toString()]?.data;
  }

  static void _setCached(
    TokensRequestModel request,
    Future<TokensResponseModel> response,
  ) => _tokensCache[request.hashCode.toString()] = _TokensCacheItem(
    data: response,
    timestamp: DateTime.now(),
  );
}
