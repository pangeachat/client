import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';

/// Grammar labels, refreshed once a day. The last labels fetched for each
/// language pair are kept after that day, for when a fetch cannot happen. See
/// grammar-analytics.instructions.md, "Morph feature inventory".
class GrammarConstructsRepo
    extends BaseRepo<GrammarConstructsRequest, GrammarConstructsResponse> {
  static final GrammarConstructsRepo _instance =
      GrammarConstructsRepo._internal();

  static GrammarConstructsRepo get instance => _instance;

  // One entry per language pair, so keeping old ones costs nothing.
  static final _savedLabels = PersistentRepoCache<GrammarConstructsResponse>(
    'grammar_constructs_storage',
    keepExpired: true,
  );

  GrammarConstructsRepo._internal()
    : super(
        cache: _savedLabels,
        responseFromJson: GrammarConstructsResponse.fromJson,
        cacheDuration: const Duration(days: 1),
      );

  /// The last labels fetched for [request], whatever their age.
  GrammarConstructsResponse? getSaved(GrammarConstructsRequest request) =>
      _savedLabels.getAnyAge(request.storageKey, responseFromJson);

  @override
  Future<Response> fetch(Requests req, GrammarConstructsRequest request) =>
      req.post(url: PApiUrls.grammarConstructs, body: request.toJson());
}
