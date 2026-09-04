import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:async/async.dart';
import 'package:http/http.dart' hide BaseRequest, BaseResponse;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/error_response_parser.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache_item.dart';
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
  final ErrorResponseParser? errorResponseParser;

  late final Future<void> _cacheInit = cache.init();

  BaseRepo({
    required this.cache,
    required this.responseFromJson,
    required this.cacheDuration,
    this.timeout = const Duration(seconds: 60),
    this.errorResponseParser,
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

    // The RETRYING operation is what goes in the inflight cache, not the first
    // attempt — a concurrent caller must join the retry and see its result,
    // not be handed the 429 the attempt it joined already returned.
    final future = _fetchThroughRateLimit(request);
    _inflightCache[key] = future;
    final result = await future;

    final response = result.result;
    if (response != null && shouldCache(response)) {
      await setCached(request, response);
    }

    _inflightCache.remove(key);
    return result;
  }

  Future<Response> fetch(Requests req, TRequest request);

  /// Whether [response] should be written to the cache. Defaults to caching
  /// every successful response; subclasses override to refuse memoizing a
  /// success that must not be pinned for the whole [cacheDuration] — e.g. an
  /// exhausted-fallback STT response with empty results, which pre-R0-2 threw
  /// (and so was never cached) but now parses gracefully and would otherwise
  /// starve retries. Annotated [visibleForTesting] so the concrete policy can
  /// be asserted directly.
  @protected
  @visibleForTesting
  bool shouldCache(TResponse response) => true;

  /// Builds the [Requests] carrier for a fetch. Isolated so the Matrix
  /// god-object token read stays out of the hot path's signature and tests can
  /// drive [get] without booting [MatrixState].
  @protected
  @visibleForTesting
  Requests createRequests() => Requests(
    accessToken: MatrixState.pangeaController.userController.accessToken,
  );

  /// Sentry level for a fetch failure — the shared severity table
  /// ([PangeaHttpException.severityOf]): timeouts and gone/routine statuses
  /// (401, 404, 410, 429) are warnings; everything else is an error.
  @visibleForTesting
  static SentryLevel errorLevel(Object e) => PangeaHttpException.severityOf(e);

  /// Key for reporting this failure once per app session
  /// ([ErrorHandler.logErrorOnce]), or null — the default — to report every
  /// occurrence. Subclasses override for failures that recur identically with
  /// no new signal, e.g. a 404 on an activity id that every surface
  /// referencing it re-reads (CLIENT-EB0, same rationale as #8083's
  /// once-per-course reporting).
  @protected
  @visibleForTesting
  String? reportOnceKey(TRequest request, Object error) => null;

  /// Whether a 429 on this repo's reads is worth waiting out and retrying once
  /// before it is surfaced.
  ///
  /// Opt-in, and false by default, because waiting is only free where the
  /// caller renders a loading state for the whole await and holds no shared
  /// resource meanwhile. `ActivityPlanRepo` is the counter-example on both
  /// counts: it dispatches behind a 6-slot in-flight bound, so a waiting read
  /// would hold a slot the rest of the view needs, and it deliberately PARKS a
  /// rate-limited key rather than re-attempting it (#8160). The word card's
  /// two reads are the opposite — one await each, straight into a shimmer
  /// (#8794).
  @protected
  @visibleForTesting
  bool get retryOnRateLimit => false;

  /// The longest a [retryOnRateLimit] repo will sit on a 429 before giving up
  /// and surfacing it.
  ///
  /// The surface shows a loading state for the whole wait, so this trades how
  /// often the retry lands against how long a shimmer stays honest. Observed
  /// throttle episodes run 2–35s (Sentry CLIENT-EB8/EB6, 14d), and choreo's
  /// limiter is per gunicorn worker with a fresh connection per request, so a
  /// retry seconds later can land on a worker that still has budget. 5s covers
  /// the short end of that without the card reading as hung; the long tail
  /// still errors, which is what #8794 asks for ("still error out if fetch
  /// time exceeds a reasonable limit").
  ///
  /// Mutable only as a test seam — the wait is wall-clock, so tests would
  /// otherwise need real delays.
  @visibleForTesting
  static Duration rateLimitRetryWait = const Duration(seconds: 5);

  /// [_fetch], plus the one bounded retry [retryOnRateLimit] asks for.
  Future<Result<TResponse>> _fetchThroughRateLimit(TRequest request) async {
    final result = await _fetch(request);
    final error = result.isError ? result.asError!.error : null;
    if (!retryOnRateLimit || !RateLimitPause.isRateLimited(error)) {
      return result;
    }

    // Never longer than the budget actually needs. `remaining` is the full
    // window today, so this is the cap in practice — but it already reads the
    // shorter answer when the pause was armed by an earlier read, and it
    // becomes the real wait the moment choreo starts sending `Retry-After`.
    final pause = RateLimitPause.forError(error);
    final remaining = pause?.remaining ?? rateLimitRetryWait;
    await Future.delayed(
      remaining < rateLimitRetryWait ? remaining : rateLimitRetryWait,
    );

    // The retry does not report on its own: the first attempt already logged
    // this 429, and a second event per read would double today's warning
    // volume for no new signal. A budget that is STILL throttled is reported
    // once per activation instead, through the same gate the suppressing repos
    // use (client#8507).
    final retried = await _fetch(request, report: false);
    if (retried.isError) {
      pause?.reportSuppressionOnce({'storage_key': request.storageKey});
    }
    return retried;
  }

  Future<Result<TResponse>> _fetch(
    TRequest request, {
    bool report = true,
  }) async {
    try {
      final Requests req = createRequests();

      // No ≥400 check here: [fetch] goes through [Requests], which already
      // threw a typed error for any failing status.
      final Response res = await fetch(req, request).timeout(timeout);

      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      return Result.value(responseFromJson(json));
    } catch (e, s) {
      Logs().w("Error: $e\n$s");
      // Before the report, so the budget is armed even if reporting throws.
      // Every repo arms it, not just the ones that wait on it: a 429 is a
      // statement about the whole budget, and the read that happens to see it
      // is rarely the read that spent it (#8794).
      RateLimitPause.forError(e)?.recordFailure(e);
      if (report && e is! UnsubscribedException) {
        final onceKey = reportOnceKey(request, e);
        if (onceKey != null) {
          ErrorHandler.logErrorOnce(
            key: onceKey,
            e: e,
            s: s,
            data: request.toJson(),
            level: errorLevel(e),
          );
        } else {
          ErrorHandler.logError(
            e: e,
            s: s,
            data: request.toJson(),
            level: errorLevel(e),
          );
        }
      }
      return Result.error(e);
    }
  }

  Future<void> setCached(TRequest request, TResponse response) async {
    await _cacheInit;
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
