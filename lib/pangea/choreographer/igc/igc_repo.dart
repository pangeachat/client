import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/choreographer/igc/igc_request_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/igc_response_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';

class _IgcCacheItem {
  final Future<IGCResponseModel> data;
  final DateTime timestamp;

  const _IgcCacheItem({
    required this.data,
    required this.timestamp,
  });
}

class _IgnoredMatchCacheItem {
  final PangeaMatch match;
  final DateTime timestamp;

  String get spanText => match.match.fullText.characters
      .skip(match.match.offset)
      .take(match.match.length)
      .toString();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _IgnoredMatchCacheItem && other.spanText == spanText;
  }

  @override
  int get hashCode => spanText.hashCode;

  _IgnoredMatchCacheItem({
    required this.match,
    required this.timestamp,
  });
}

class IgcRepo {
  static final Map<String, _IgcCacheItem> _igcCache = {};
  static final Map<String, _IgnoredMatchCacheItem> _ignoredMatchCache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<Result<IGCResponseModel>> get(
    String? accessToken,
    IGCRequestModel igcRequest,
  ) {
    debugPrint(
        '[IgcRepo.get] called, request.hashCode: ${igcRequest.hashCode}');
    final cached = _getCached(igcRequest);
    if (cached != null) {
      debugPrint('[IgcRepo.get] cache HIT');
      return _getResult(igcRequest, cached);
    }
    debugPrint('[IgcRepo.get] cache MISS, fetching from server...');

    final future = _fetch(
      accessToken,
      igcRequest: igcRequest,
    );
    _setCached(igcRequest, future);
    return _getResult(igcRequest, future);
  }

  static Future<IGCResponseModel> _fetch(
    String? accessToken, {
    required IGCRequestModel igcRequest,
  }) async {
    final Requests req = Requests(
      accessToken: accessToken,
      choreoApiKey: Environment.choreoApiKey,
    );
    final Response res = await req.post(
      url: PApiUrls.igcLite,
      body: igcRequest.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to fetch IGC data: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(res.bodyBytes).toString());

    return IGCResponseModel.fromJson(json);
  }

  static Future<Result<IGCResponseModel>> _getResult(
    IGCRequestModel request,
    Future<IGCResponseModel> future,
  ) async {
    try {
      final res = await future;
      return Result.value(res);
    } catch (e, s) {
      _igcCache.remove(request.hashCode.toString());
      ErrorHandler.logError(
        e: e,
        s: s,
        data: request.toJson(),
      );
      return Result.error(e);
    }
  }

  static Future<IGCResponseModel>? _getCached(
    IGCRequestModel request,
  ) {
    final cacheKeys = [..._igcCache.keys];
    for (final key in cacheKeys) {
      if (_igcCache[key]!
          .timestamp
          .isBefore(DateTime.now().subtract(_cacheDuration))) {
        _igcCache.remove(key);
      }
    }

    return _igcCache[request.hashCode.toString()]?.data;
  }

  static void _setCached(
    IGCRequestModel request,
    Future<IGCResponseModel> response,
  ) =>
      _igcCache[request.hashCode.toString()] = _IgcCacheItem(
        data: response,
        timestamp: DateTime.now(),
      );

  static void ignore(PangeaMatch match) {
    _setCachedIgnoredSpan(match);
  }

  static bool isIgnored(PangeaMatch match) {
    final cached = _getCachedIgnoredSpan(match);
    return cached != null;
  }

  static PangeaMatch? _getCachedIgnoredSpan(
    PangeaMatch match,
  ) {
    final cacheKeys = [..._ignoredMatchCache.keys];
    for (final key in cacheKeys) {
      final entry = _ignoredMatchCache[key]!;
      if (DateTime.now().difference(entry.timestamp) >= _cacheDuration) {
        _ignoredMatchCache.remove(key);
      }
    }

    final cacheEntry = _IgnoredMatchCacheItem(
      match: match,
      timestamp: DateTime.now(),
    );
    return _ignoredMatchCache[cacheEntry.hashCode.toString()]?.match;
  }

  static void _setCachedIgnoredSpan(
    PangeaMatch match,
  ) {
    final cacheEntry = _IgnoredMatchCacheItem(
      match: match,
      timestamp: DateTime.now(),
    );
    _ignoredMatchCache[cacheEntry.hashCode.toString()] = cacheEntry;
  }
}
