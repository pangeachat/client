import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' hide BaseResponse, BaseRequest;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class RepoCacheItem<TResponse extends BaseResponse> {
  final DateTime timestamp;
  final TResponse response;

  const RepoCacheItem({required this.timestamp, required this.response});

  bool isExpired(Duration cacheDuration) =>
      timestamp.isBefore(DateTime.now().subtract(cacheDuration));

  Map<String, dynamic> toJson() => {
    "timestamp": timestamp.millisecondsSinceEpoch,
    "response": response.toJson(),
  };

  factory RepoCacheItem.fromJson(
    Map<String, dynamic> json, {
    required TResponse Function(Map<String, dynamic>) responseFromJson,
  }) {
    return RepoCacheItem(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json["timestamp"]),
      response: responseFromJson(json["response"]),
    );
  }
}

abstract class BaseRepo<
  TRequest extends BaseRequest,
  TResponse extends BaseResponse
> {
  final Map<String, Future<Result<TResponse>>> _inflightCache = {};
  final Duration cacheDuration;
  final Duration timeout;
  final TResponse Function(Map<String, dynamic>) responseFromJson;

  /// When false the cache is in-memory only (dropped on app restart). Use it
  /// for volatile data that should not survive a restart, or where persisting
  /// would risk stale entries. Default persists to disk via GetStorage.
  final bool persist;

  final GetStorage? _storage;
  final Map<String, RepoCacheItem<TResponse>> _memoryCache = {};

  late final Future<bool> _storageInit;

  BaseRepo({
    required String boxName,
    required this.responseFromJson,
    required this.cacheDuration,
    this.persist = true,
    this.timeout = const Duration(seconds: 60),
  }) : _storage = persist ? GetStorage(boxName) : null {
    if (persist) {
      _storageInit = GetStorage.init(boxName);
      MatrixState.pangeaController.registerStorageKey(boxName);
    } else {
      _storageInit = Future.value(true);
    }
  }

  /// Fetch [request], cached: a fresh cached value when present, else fetches
  /// (deduplicating concurrent calls for the same key) and caches the result.
  /// The fetch deadline is the repo-level [timeout], so concurrent callers
  /// share one well-defined timeout.
  Future<Result<TResponse>> get(TRequest request) async {
    await _storageInit;
    final cached = getCached(request);
    if (cached != null) {
      return Result.value(cached);
    }

    final key = request.storageKey;
    final inflight = _inflightCache[key];
    if (inflight != null) {
      return inflight;
    }

    final future = _fetch(request);
    _inflightCache[key] = future;
    final result = await future;

    final response = result.result;
    if (response != null) {
      await setCached(request, response);
    }

    _inflightCache.remove(key);
    return result;
  }

  Future<Response> fetch(Requests req, TRequest request);

  Future<Result<TResponse>> _fetch(TRequest request) async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        choreoApiKey: Environment.choreoApiKey,
      );

      final Response res = await fetch(req, request).timeout(timeout);
      if (res.statusCode >= 400) {
        throw res;
      }

      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      return Result.value(responseFromJson(json));
    } catch (e, s) {
      Logs().w("Error: $e\n$s");
      if (e is! UnsubscribedException) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: request.toJson(),
          level: e is TimeoutException
              ? SentryLevel.warning
              : SentryLevel.error,
        );
      }
      return Result.error(e);
    }
  }

  Future<void> setCached(TRequest request, TResponse response) async {
    final item = RepoCacheItem<TResponse>(
      timestamp: DateTime.now(),
      response: response,
    );
    if (persist) {
      await _storage!.write(request.storageKey, item.toJson());
    } else {
      _memoryCache[request.storageKey] = item;
    }
  }

  TResponse? getCached(TRequest request) {
    final key = request.storageKey;

    if (!persist) {
      final item = _memoryCache[key];
      if (item == null) return null;
      if (item.isExpired(cacheDuration)) {
        _memoryCache.remove(key);
        return null;
      }
      return item.response;
    }

    final entry = _storage!.read(key);
    if (entry == null) return null;
    try {
      final value = RepoCacheItem<TResponse>.fromJson(
        entry,
        responseFromJson: responseFromJson,
      );
      if (value.isExpired(cacheDuration)) {
        _storage.remove(key);
        return null;
      }
      return value.response;
    } catch (_) {
      _storage.remove(key);
      return null;
    }
  }

  /// Drop the cached entry for [request] (e.g. after it changed server-side) so
  /// the next [get] refetches. Also clears any in-flight fetch for that key.
  Future<void> invalidate(TRequest request) async {
    await _storageInit;
    final key = request.storageKey;
    _inflightCache.remove(key);
    if (persist) {
      await _storage!.remove(key);
    } else {
      _memoryCache.remove(key);
    }
  }

  /// Drop the entire cache.
  Future<void> clearCache() async {
    await _storageInit;
    _inflightCache.clear();
    _memoryCache.clear();
    if (persist) await _storage!.erase();
  }
}
