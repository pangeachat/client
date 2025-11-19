import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_request.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_response.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';

class _SpanDetailsCacheItem {
  final Future<SpanData> data;
  final DateTime timestamp;

  const _SpanDetailsCacheItem({
    required this.data,
    required this.timestamp,
  });
}

class SpanDataRepo {
  static final Map<String, _SpanDetailsCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<Result<SpanData>> get(
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

  static Future<SpanData> _fetch(
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

    final respModel = SpanDetailsResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
    return respModel.span;
  }

  static Future<Result<SpanData>> _getResult(
    SpanDetailsRequest request,
    Future<SpanData> future,
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

  static Future<SpanData>? _getCached(
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
    Future<SpanData> response,
  ) {
    _cache[request.hashCode.toString()] = _SpanDetailsCacheItem(
      data: response,
      timestamp: DateTime.now(),
    );
  }
}
