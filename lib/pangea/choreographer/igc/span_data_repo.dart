import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/choreographer/igc/span_data_request.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_response.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';

class _SpanDetailsCacheItem {
  final Future<SpanDetailsResponse> data;
  final DateTime timestamp;

  const _SpanDetailsCacheItem({
    required this.data,
    required this.timestamp,
  });
}

class SpanDataRepo {
  static final Map<String, _SpanDetailsCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<Result<SpanDetailsResponse>> get(
    String? accessToken, {
    required SpanDetailsRequest request,
  }) async {
    final cached = _getCached(request);
    if (cached != null) {
      return _getResult(request, cached);
    }

    final future = _fetch(
      accessToken,
      request: request,
    );
    _setCached(request, future);
    return _getResult(request, future);
  }

  static Future<SpanDetailsResponse> _fetch(
    String? accessToken, {
    required SpanDetailsRequest request,
  }) async {
    final Requests req = Requests(
      accessToken: accessToken,
      choreoApiKey: Environment.choreoApiKey,
    );

    final Response res = await req.post(
      url: PApiUrls.spanDetails,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to load span details');
    }

    return SpanDetailsResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
  }

  static Future<Result<SpanDetailsResponse>> _getResult(
    SpanDetailsRequest request,
    Future<SpanDetailsResponse> future,
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

  static Future<SpanDetailsResponse>? _getCached(
    SpanDetailsRequest request,
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
    SpanDetailsRequest request,
    Future<SpanDetailsResponse> response,
  ) {
    _cache[request.hashCode.toString()] = _SpanDetailsCacheItem(
      data: response,
      timestamp: DateTime.now(),
    );
  }
}
