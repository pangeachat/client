import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_request.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_response.dart';

class _PhoneticTranscriptionMemoryCacheItem {
  final Future<Result<PhoneticTranscriptionResponse>> resultFuture;
  final DateTime timestamp;

  const _PhoneticTranscriptionMemoryCacheItem({
    required this.resultFuture,
    required this.timestamp,
  });
}

class _PhoneticTranscriptionStorageCacheItem {
  final PhoneticTranscriptionResponse response;
  final DateTime timestamp;

  const _PhoneticTranscriptionStorageCacheItem({
    required this.response,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'response': response.toJson(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static _PhoneticTranscriptionStorageCacheItem fromJson(
    Map<String, dynamic> json,
  ) {
    return _PhoneticTranscriptionStorageCacheItem(
      response: PhoneticTranscriptionResponse.fromJson(json['response']),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class PhoneticTranscriptionRepo {
  // In-memory cache
  static final Map<String, _PhoneticTranscriptionMemoryCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);
  static const Duration _storageDuration = Duration(days: 7);

// Persistent storage
  static final GetStorage _storage =
      GetStorage('phonetic_transcription_storage');

  static Future<Result<PhoneticTranscriptionResponse>> get(
    String accessToken,
    PhoneticTranscriptionRequest request,
  ) async {
    await GetStorage.init('phonetic_transcription_storage');

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
    _cache[request.hashCode.toString()] = _PhoneticTranscriptionMemoryCacheItem(
      resultFuture: future,
      timestamp: DateTime.now(),
    );

    // 5. Write to disk *after* the fetch finishes, without rethrowing
    writeToDisk(request, future);

    return future;
  }

  static Future<void> set(
    PhoneticTranscriptionRequest request,
    PhoneticTranscriptionResponse resultFuture,
  ) async {
    await GetStorage.init('phonetic_transcription_storage');
    final key = request.hashCode.toString();
    try {
      final item = _PhoneticTranscriptionStorageCacheItem(
        response: resultFuture,
        timestamp: DateTime.now(),
      );
      await _storage.write(key, item.toJson());
      _cache.remove(key); // Invalidate in-memory cache
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'request': request.toJson()},
      );
    }
  }

  static Future<Result<PhoneticTranscriptionResponse>> _safeFetch(
    String token,
    PhoneticTranscriptionRequest request,
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

  static Future<PhoneticTranscriptionResponse> _fetch(
    String accessToken,
    PhoneticTranscriptionRequest request,
  ) async {
    final req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.phoneticTranscription,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw HttpException(
        'Failed to fetch phonetic transcription: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    return PhoneticTranscriptionResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
  }

  static Future<Result<PhoneticTranscriptionResponse>>? _getCached(
    PhoneticTranscriptionRequest request,
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
    PhoneticTranscriptionRequest request,
    Future<Result<PhoneticTranscriptionResponse>> resultFuture,
  ) async {
    final result = await resultFuture; // SAFE: never throws

    if (!result.isValue) return; // only cache successful responses
    await set(request, result.asValue!.value);
  }

  static PhoneticTranscriptionResponse? _getStored(
    PhoneticTranscriptionRequest request,
  ) {
    final key = request.hashCode.toString();
    try {
      final entry = _storage.read(key);
      if (entry == null) return null;

      final item = _PhoneticTranscriptionStorageCacheItem.fromJson(entry);
      if (DateTime.now().difference(item.timestamp) >= _storageDuration) {
        _storage.remove(key);
        return null;
      }
      return item.response;
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
