import 'package:async/async.dart';
import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';

/// Grammar labels, refreshed once a day. The last labels fetched for each
/// language pair are kept after that day, for when a fetch cannot happen, and
/// a pair whose fetch failed is not fetched again for [retryFailedFetchAfter].
/// See grammar-analytics.instructions.md, "Morph feature inventory".
class GrammarConstructsRepo
    extends BaseRepo<GrammarConstructsRequest, GrammarConstructsResponse> {
  static final GrammarConstructsRepo _instance =
      GrammarConstructsRepo._internal();

  static GrammarConstructsRepo get instance => _instance;

  /// How long a failed fetch holds off the next one for the same pair. Every
  /// surface that reads the labels asks this repo, so without a hold a pair
  /// the server cannot build was fetched on each analytics or practice entry,
  /// and each try is an LLM call there (#9604). The saved or built-in labels
  /// stand in meanwhile.
  static const Duration retryFailedFetchAfter = Duration(hours: 1);

  // One entry per language pair, so keeping old ones costs nothing.
  static final _savedLabels = PersistentRepoCache<GrammarConstructsResponse>(
    'grammar_constructs_storage',
    keepExpired: true,
  );

  final Map<String, _FailedFetch> _failed = {};

  GrammarConstructsRepo._internal()
    : super(
        cache: _savedLabels,
        responseFromJson: GrammarConstructsResponse.fromJson,
        cacheDuration: const Duration(days: 1),
      );

  /// The last labels fetched for [request], whatever their age.
  GrammarConstructsResponse? getSaved(GrammarConstructsRequest request) =>
      _savedLabels.getAnyAge(request.storageKey, responseFromJson);

  /// [BaseRepo.get], except that a pair whose last fetch failed within
  /// [retryFailedFetchAfter] is answered with that failure instead of a new
  /// request. The failure was reported when it happened; the hold reports
  /// nothing. A [forceRefresh] is a deliberate retry and is never held.
  @override
  Future<Result<GrammarConstructsResponse>> get(
    GrammarConstructsRequest request, {
    bool forceRefresh = false,
  }) async {
    final key = request.storageKey;
    final failed = _failed[key];
    if (failed != null && !forceRefresh && !failed.lapsed) {
      return Result.error(failed.error);
    }

    final result = await super.get(request, forceRefresh: forceRefresh);
    final error = result.asError?.error;
    if (error == null) {
      _failed.remove(key);
    } else {
      _failed[key] = _FailedFetch(error);
    }
    return result;
  }

  @override
  Future<void> invalidate(GrammarConstructsRequest request) {
    _failed.remove(request.storageKey);
    return super.invalidate(request);
  }

  @override
  Future<void> clearCache() {
    _failed.clear();
    return super.clearCache();
  }

  @override
  Future<Response> fetch(Requests req, GrammarConstructsRequest request) =>
      req.post(url: PApiUrls.grammarConstructs, body: request.toJson());
}

/// One failed fetch: what the caller was told, and when the hold on its pair
/// ends. On the shared [RateLimitPause.now] clock, so tests can move it.
class _FailedFetch {
  final Object error;
  final DateTime until;

  _FailedFetch(this.error)
    : until = RateLimitPause.now().add(
        GrammarConstructsRepo.retryFailedFetchAfter,
      );

  bool get lapsed => !RateLimitPause.now().isBefore(until);
}
