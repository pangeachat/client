import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_models.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

class _MemoryCacheItem {
  final Future<Result<PTResponse>> resultFuture;
  final DateTime timestamp;

  const _MemoryCacheItem({
    required this.resultFuture,
    required this.timestamp,
  });
}

class _DiskCacheItem {
  final PTResponse response;
  final DateTime timestamp;

  const _DiskCacheItem({required this.response, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'response': response.toJson(),
        'timestamp': timestamp.toIso8601String(),
      };

  static _DiskCacheItem fromJson(Map<String, dynamic> json) {
    return _DiskCacheItem(
      response: PTResponse.fromJson(json['response']),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

const String ptV2StorageKey = 'phonetic_transcription_v2_storage';

class PTV2Repo {
  static final Map<String, _MemoryCacheItem> _cache = {};
  static const Duration _memoryCacheDuration = Duration(minutes: 10);
  static const Duration _diskCacheDuration = Duration(hours: 24);

  static final GetStorage _storage = GetStorage(ptV2StorageKey);

  static Future<Result<PTResponse>> get(
    String accessToken,
    PTRequest request,
  ) async {
    await GetStorage.init(ptV2StorageKey);

    // 1. Try memory cache
    final cached = _getCached(request);
    if (cached != null) return cached;

    // 2. Try disk cache
    final stored = _getStored(request);
    if (stored != null) return Future.value(Result.value(stored));

    // 3. Fetch from network
    final future = _safeFetch(accessToken, request);

    // 4. Save to in-memory cache
    _cache[request.cacheKey] = _MemoryCacheItem(
      resultFuture: future,
      timestamp: DateTime.now(),
    );

    // 5. Write to disk after fetch completes
    _writeToDisk(request, future);

    return future;
  }

  /// Overwrite a cached response (used by token feedback to refresh stale PT).
  static Future<void> set(PTRequest request, PTResponse response) async {
    await GetStorage.init(ptV2StorageKey);
    final key = request.cacheKey;
    try {
      final item = _DiskCacheItem(response: response, timestamp: DateTime.now());
      await _storage.write(key, item.toJson());
      _cache.remove(key);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'cacheKey': key});
    }
  }

  static Future<Result<PTResponse>>? _getCached(PTRequest request) {
    final now = DateTime.now();
    _cache.removeWhere(
      (_, item) => now.difference(item.timestamp) >= _memoryCacheDuration,
    );
    return _cache[request.cacheKey]?.resultFuture;
  }

  static PTResponse? _getStored(PTRequest request) {
    final key = request.cacheKey;
    try {
      final entry = _storage.read(key);
      if (entry == null) return null;

      final item = _DiskCacheItem.fromJson(entry);
      if (DateTime.now().difference(item.timestamp) >= _diskCacheDuration) {
        _storage.remove(key);
        return null;
      }
      return item.response;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'cacheKey': key});
      _storage.remove(key);
      return null;
    }
  }

  static Future<Result<PTResponse>> _safeFetch(
    String token,
    PTRequest request,
  ) async {
    try {
      final resp = await _fetch(token, request);
      return Result.value(resp);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }

  static Future<PTResponse> _fetch(
    String accessToken,
    PTRequest request,
  ) async {
    final req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.phoneticTranscriptionV2,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw HttpException(
        'Failed to fetch phonetic transcription v2: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    return PTResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  static Future<void> _writeToDisk(
    PTRequest request,
    Future<Result<PTResponse>> resultFuture,
  ) async {
    final result = await resultFuture;
    if (!result.isValue) return;
    await set(request, result.asValue!.value);
  }
}
