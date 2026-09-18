import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';

/// Disk-cached lemma dictionary info (`POST /lemma_dictionary`).
/// `persist: true` — lemma meanings are stable and worth keeping across
/// restarts.
class LemmaInfoRepo extends BaseRepo<LemmaInfoRequest, LemmaInfoResponse> {
  LemmaInfoRepo._internal()
    : super(
        cache: PersistentRepoCache<LemmaInfoResponse>('lemma_storage'),
        responseFromJson: LemmaInfoResponse.fromJson,
        cacheDuration: const Duration(minutes: 10),
      );

  static final LemmaInfoRepo _instance = LemmaInfoRepo._internal();
  static LemmaInfoRepo get instance => _instance;

  /// Its callers await it behind a loading state — the word card's shimmer
  /// (#8794), analytics practice before it marks an exercise ready — so a
  /// short throttle waited out costs a longer load rather than an error the
  /// learner cannot act on. `BaseRepo.maxRateLimitWait` bounds how long.
  @override
  bool get retryOnRateLimit => true;

  @override
  Future<Response> fetch(Requests req, LemmaInfoRequest request) =>
      req.post(url: PApiUrls.lemmaDictionary, body: request.toJson());
}
