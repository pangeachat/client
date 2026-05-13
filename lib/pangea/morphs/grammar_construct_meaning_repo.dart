import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_meaning_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_meaning_response.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class GrammarConstructMeaningRepo
    extends
        BaseRepo<
          GrammarConstructMeaningRequest,
          GrammarConstructMeaningResponse
        > {
  static final GrammarConstructMeaningRepo _instance =
      GrammarConstructMeaningRepo._internal();

  static GrammarConstructMeaningRepo get instance => _instance;

  GrammarConstructMeaningRepo._internal()
    : super(
        boxName: 'grammar_construct_meanings_storage',
        responseFromJson: GrammarConstructMeaningResponse.fromJson,
        cacheDuration: const Duration(days: 1),
      );

  @override
  Future<Response> fetch(
    Requests req,
    GrammarConstructMeaningRequest request,
  ) => req.post(url: PApiUrls.grammarConstructMeaning, body: request.toJson());

  Future<void> setMeaning({
    required GrammarConstructMeaningRequest request,
    required String tag,
    required String description,
  }) async {
    final result = await get(request);
    final response = result.result;
    if (response == null) return;

    final cachedTag = response.getTag(tag);
    if (cachedTag == null) return;

    final updatedTag = cachedTag.copyWith(description: description);
    final updatedMeaning = response.copyWithMeaning(meaning: updatedTag);
    await setCached(request, updatedMeaning);
  }
}
