import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';

class _LemmaInfoCacheItem {
  final Future<Result<LemmaInfoResponse>> resultFuture;
  final DateTime timestamp;

  const _LemmaInfoCacheItem({
    required this.resultFuture,
    required this.timestamp,
  });
}

class LemmaInfoRepo {
  // In-memory cache
  static final Map<String, _LemmaInfoCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  // Persistent storage
  static final GetStorage _storage = GetStorage('lemma_storage');

  /// Public entry point
  static Future<Result<LemmaInfoResponse>> get(
    String accessToken,
    LemmaInfoRequest request,
  ) async {
    await GetStorage.init('lemma_storage');

    // 1. Try memory cache
    final cached = _getCached(request);
    if (cached != null) {
      return cached;
    }

    // 2. Try disk cache
    final stored = _getStored(request);
    if (stored != null) {
      return Result.value(stored);
    }

    // 3. Fetch from network (safe future)
    final future = _safeFetch(accessToken, request);

    // 4. Save to in-memory cache
    _cache[request.hashCode.toString()] = _LemmaInfoCacheItem(
      resultFuture: future,
      timestamp: DateTime.now(),
    );

    // 5. Write to disk *after* the fetch finishes, without rethrowing
    writeToDisk(request, future);

    return future;
  }

  static Future<void> set(
    LemmaInfoRequest request,
    LemmaInfoResponse resultFuture,
  ) async {
    await GetStorage.init('lemma_storage');

    final key = request.hashCode.toString();
    try {
      await _storage.write(key, resultFuture.toJson());
      _cache.remove(key); // Invalidate in-memory cache
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'lemma': request.lemma},
      );
    }
  }

  ///clear cache of a specific request to retry if failed
  static void clearCache(LemmaInfoRequest request) {
    final key = request.hashCode.toString();
    _cache.remove(key);
  }

  static void clearAllCache() {
    _cache.clear();
  }

  static Future<Result<LemmaInfoResponse>> _safeFetch(
    String token,
    LemmaInfoRequest request,
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

  static Future<LemmaInfoResponse> _fetch(
    String accessToken,
    LemmaInfoRequest request,
  ) async {
    final req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.lemmaDictionary,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw HttpException(
        'Failed to fetch lemma info: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    return LemmaInfoResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
  }

  static Future<Result<LemmaInfoResponse>>? _getCached(
    LemmaInfoRequest request,
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
    LemmaInfoRequest request,
    Future<Result<LemmaInfoResponse>> resultFuture,
  ) async {
    final result = await resultFuture; // SAFE: never throws

    if (!result.isValue) return; // only cache successful responses
    await set(request, result.asValue!.value);
  }

  static LemmaInfoResponse? _getStored(
    LemmaInfoRequest request,
  ) {
    final key = request.hashCode.toString();
    try {
      final entry = _storage.read(key);
      if (entry == null) return null;

      return LemmaInfoResponse.fromJson(entry);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'lemma': request.lemma},
      );
      _storage.remove(key);
      return null;
    }
  }
}
