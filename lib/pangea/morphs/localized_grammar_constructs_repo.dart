import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/localized_grammar_constructs_response.dart';

class LocalizedGrammarConstructsRepo
    extends
        BaseRepo<GrammarConstructsRequest, LocalizedGrammarConstructsResponse> {
  static LocalizedGrammarConstructsRepo? _instance;

  static LocalizedGrammarConstructsRepo instance({
    required void Function(String) registerBoxName,
  }) {
    _instance ??= LocalizedGrammarConstructsRepo._internal(
      registerBoxName: registerBoxName,
    );
    return _instance!;
  }

  LocalizedGrammarConstructsRepo._internal({required super.registerBoxName})
    : super(
        boxName: 'localized_grammar_constructs_storage',
        responseFromJson: LocalizedGrammarConstructsResponse.fromJson,
        cacheDuration: const Duration(days: 1),
      );

  @override
  Future<Response> fetch(Requests req, GrammarConstructsRequest request) =>
      req.post(url: PApiUrls.grammarConstructs, body: request.toJson());
}
