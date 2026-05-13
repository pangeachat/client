import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_meaning_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_meaning_response.dart';

class GrammarConstructMeaningRepo
    extends
        BaseRepo<
          GrammarConstructMeaningRequest,
          GrammarConstructMeaningResponse
        > {
  static GrammarConstructMeaningRepo? _instance;

  static GrammarConstructMeaningRepo instance({
    required void Function(String) registerBoxName,
  }) {
    _instance ??= GrammarConstructMeaningRepo._internal(
      registerBoxName: registerBoxName,
    );
    return _instance!;
  }

  GrammarConstructMeaningRepo._internal({required super.registerBoxName})
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
}
