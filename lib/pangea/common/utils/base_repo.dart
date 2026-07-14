import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart' hide BaseRequest, BaseResponse;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:meta/meta.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

abstract class BaseRepo<
  TRequest extends BaseRequest,
  TResponse extends BaseResponse
> {
  final RepoCache<TResponse> cache;

  final Map<String, Future<Result<TResponse>>> _inflightCache = {};

  final Duration cacheDuration;
  final Duration timeout;
  final TResponse Function(Map<String, dynamic>) responseFromJson;

  late final Future<void> _cacheInit = cache.init();

  BaseRepo({
    required this.cache,
    required this.responseFromJson,
    required this.cacheDuration,
    this.timeout = const Duration(seconds: 60),
  });

  /// Fetch [request], cached: a fresh cached value when present, else fetches
  /// (deduplicating concurrent calls for the same key) and caches the result.
  /// The fetch deadline is the repo-level [timeout], so concurrent callers
  /// share one well-defined timeout.
  /// [forceRefresh] skips the cache READ and fetches fresh, then overwrites the
  /// cache. The existing cached value is left in place until the fresh response
  /// lands (via [setCached]), so a concurrent [getCached] keeps returning the
  /// stale value rather than null — stale-while-revalidate, no loading flicker.
  Future<Result<TResponse>> get(
    TRequest request, {
    bool forceRefresh = false,
  }) async {
    await _cacheInit;
    if (!forceRefresh) {
      final cached = getCached(request);
      if (cached != null) {
        return Result.value(cached);
      }
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

  /// Sentry level for a fetch failure. Timeouts and confirmed 404s are
  /// warnings — a 404 means the resource is gone (expected for e.g. removed
  /// activities referenced by old rooms), not that code broke.
  @visibleForTesting
  static SentryLevel errorLevel(Object e) =>
      e is TimeoutException || (e is Response && e.statusCode == 404)
      ? SentryLevel.warning
      : SentryLevel.error;

  Future<Result<TResponse>> _fetch(TRequest request) async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
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
          level: errorLevel(e),
        );
      }
      return Result.error(e);
    }
  }

  Future<void> setCached(TRequest request, TResponse response) {
    return cache.set(
      request.storageKey,
      RepoCacheItem(timestamp: DateTime.now(), response: response),
    );
  }

  TResponse? getCached(TRequest request) {
    return cache.get(request.storageKey, cacheDuration, responseFromJson);
  }

  Future<void> invalidate(TRequest request) async {
    await _cacheInit;
    _inflightCache.remove(request.storageKey);
    await cache.remove(request.storageKey);
  }

  Future<void> clearCache() async {
    await _cacheInit;
    _inflightCache.clear();
    await cache.clear();
  }
}
