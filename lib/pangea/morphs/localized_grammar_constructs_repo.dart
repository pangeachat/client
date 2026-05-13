import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/localized_grammar_constructs_response.dart';

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
}
