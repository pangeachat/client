import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_features_response.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';

class GrammarConstructFeaturesRepo
    extends
        BaseRepo<GrammarConstructsRequest, GrammarConstructFeaturesResponse> {
  static final GrammarConstructFeaturesRepo _instance =
      GrammarConstructFeaturesRepo._internal();

  static GrammarConstructFeaturesRepo get instance => _instance;

  GrammarConstructFeaturesRepo._internal()
    : super(
        boxName: 'grammar_construct_features_storage',
        responseFromJson: GrammarConstructFeaturesResponse.fromJson,
        cacheDuration: const Duration(days: 1),
      );

  @override
  Future<Response> fetch(Requests req, GrammarConstructsRequest request) =>
      req.post(url: PApiUrls.grammarConstructFeatures, body: request.toJson());
}
