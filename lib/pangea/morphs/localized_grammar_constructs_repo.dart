import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/localized_grammar_constructs_response.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class LocalizedGrammarConstructsRepo
    extends
        BaseRepo<GrammarConstructsRequest, LocalizedGrammarConstructsResponse> {
  static final LocalizedGrammarConstructsRepo _instance =
      LocalizedGrammarConstructsRepo._internal();

  static LocalizedGrammarConstructsRepo get instance => _instance;

  LocalizedGrammarConstructsRepo._internal()
    : super(
        boxName: 'localized_grammar_constructs_storage',
        responseFromJson: LocalizedGrammarConstructsResponse.fromJson,
        cacheDuration: const Duration(days: 1),
      );

  @override
  Future<Response> fetch(Requests req, GrammarConstructsRequest request) =>
      req.post(url: PApiUrls.grammarConstructs, body: request.toJson());

  Future<void> setMeaning({
    required GrammarConstructsRequest request,
    required String feature,
    required String tag,
    required String description,
  }) async {
    final result = await get(request);
    final response = result.result;
    if (response == null) return;

    final cachedTag = response.getFeature(feature)?.getTag(tag);
    if (cachedTag == null) return;

    final updatedTag = cachedTag.copyWith(description: description);
    final updatedMeaning = response.copyWithMeaning(
      feature: feature,
      meaning: updatedTag,
    );
    await setCached(request, updatedMeaning);
  }
}
