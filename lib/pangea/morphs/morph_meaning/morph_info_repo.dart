import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning/morph_info_request.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning/morph_info_response.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class _MorphInfoCacheItem {
  final Future<Result<MorphInfoResponse>> resultFuture;
  final DateTime timestamp;

  const _MorphInfoCacheItem({
    required this.resultFuture,
    required this.timestamp,
  });
}

class MorphInfoRepo {
  // In-memory cache
  static final Map<String, _MorphInfoCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

// Persistent storage
  static final GetStorage _storage = GetStorage('morph_info_storage');

  static Future<Result<MorphInfoResponse>> get(
    String accessToken,
    MorphInfoRequest request,
  ) {
    // 1. Try memory cache
    final cached = _getCached(request);
    if (cached != null) {
      return cached;
    }

    // 2. Try disk cache
    final stored = _getStored(request);
    if (stored != null) {
      return Future.value(Result.value(stored));
    }

    // 3. Fetch from network (safe future)
    final future = _safeFetch(accessToken, request);

    // 4. Save to in-memory cache
    _cache[request.hashCode.toString()] = _MorphInfoCacheItem(
      resultFuture: future,
      timestamp: DateTime.now(),
    );

    // 5. Write to disk *after* the fetch finishes, without rethrowing
    writeToDisk(request, future);

    return future;
  }

  static Future<void> set(
    MorphInfoRequest request,
    MorphInfoResponse resultFuture,
  ) async {
    final key = request.hashCode.toString();
    try {
      await _storage.write(key, resultFuture.toJson());
      _cache.remove(key); // Invalidate in-memory cache
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'request': request.toJson()},
      );
    }
  }

  static Future<void> update(
    MorphInfoRequest request, {
    required MorphFeaturesEnum feature,
    required String tag,
    required String definition,
  }) async {
    try {
      final cachedJson = await _getCached(request);
      final resp = cachedJson?.result ??
          MorphInfoResponse(
            userL1: request.userL1,
            userL2: request.userL2,
            features: [],
          );

      resp.setMorphDefinition(feature.name, tag, definition);
      await set(request, resp);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'request': request.toJson()},
      );
    }
  }

  static Future<Result<MorphInfoResponse>> _safeFetch(
    String token,
    MorphInfoRequest request,
  ) async {
    try {
      final resp = await _fetch(token, request);
      return Result.value(resp);
    } catch (e, s) {
      // Ensure error is logged and converted to a Result
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }

  static Future<MorphInfoResponse> _fetch(
    String accessToken,
    MorphInfoRequest request,
  ) async {
    final req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.morphDictionary,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw HttpException(
        'Failed to fetch morph info: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    return MorphInfoResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
  }

  static Future<Result<MorphInfoResponse>>? _getCached(
    MorphInfoRequest request,
  ) {
    final now = DateTime.now();
    final key = request.hashCode.toString();

    // Remove stale entries first
    _cache.removeWhere(
      (_, item) => now.difference(item.timestamp) >= _cacheDuration,
    );

    final item = _cache[key];
    return item?.resultFuture;
  }

  static Future<void> writeToDisk(
    MorphInfoRequest request,
    Future<Result<MorphInfoResponse>> resultFuture,
  ) async {
    final result = await resultFuture; // SAFE: never throws

    if (!result.isValue) return; // only cache successful responses
    await set(request, result.asValue!.value);
  }

  static MorphInfoResponse? _getStored(
    MorphInfoRequest request,
  ) {
    final key = request.hashCode.toString();
    try {
      final entry = _storage.read(key);
      if (entry == null) return null;

      return MorphInfoResponse.fromJson(entry);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'request': request.toJson()},
      );
      _storage.remove(key);
      return null;
    }
  }
}
