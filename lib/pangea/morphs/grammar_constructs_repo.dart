import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';

class GrammarConstructsRepo
    extends BaseRepo<GrammarConstructsRequest, GrammarConstructsResponse> {
  static final GrammarConstructsRepo _instance =
      GrammarConstructsRepo._internal();

  static GrammarConstructsRepo get instance => _instance;

  GrammarConstructsRepo._internal()
    : super(
        boxName: 'grammar_constructs_storage',
        responseFromJson: GrammarConstructsResponse.fromJson,
        cacheDuration: const Duration(days: 1),
      );

  @override
  Future<Response> fetch(Requests req, GrammarConstructsRequest request) =>
      req.post(url: PApiUrls.grammarConstructs, body: request.toJson());
}
