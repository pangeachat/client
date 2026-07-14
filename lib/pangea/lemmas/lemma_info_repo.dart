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

  @override
  Future<Response> fetch(Requests req, LemmaInfoRequest request) =>
      req.post(url: PApiUrls.lemmaDictionary, body: request.toJson());
}
