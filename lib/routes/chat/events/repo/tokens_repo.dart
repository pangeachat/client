import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';

/// In-memory cached tokenization (`POST /tokenize`).
/// `persist: false` — short-lived per-message token results aren't worth
/// keeping across restarts.
class TokensRepo extends BaseRepo<TokensRequestModel, TokensResponseModel> {
  TokensRepo._internal()
    : super(
        cache: MemoryRepoCache<TokensResponseModel>(),
        responseFromJson: TokensResponseModel.fromJson,
        cacheDuration: const Duration(minutes: 10),
      );

  static final TokensRepo _instance = TokensRepo._internal();
  static TokensRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, TokensRequestModel request) =>
      req.post(url: PApiUrls.tokenize, body: request.toJson());
}
