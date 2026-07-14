import 'package:http/http.dart' show Response;

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_request_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_response_model.dart';

/// In-memory cached in-context grammar (`POST /grammar_v2`).
/// `persist: false` — short-lived per-message corrections aren't worth keeping
/// across restarts.
class IgcRepo extends BaseRepo<IGCRequestModel, IGCResponseModel> {
  IgcRepo._internal()
    : super(
        cache: MemoryRepoCache<IGCResponseModel>(),
        responseFromJson: IGCResponseModel.fromJson,
        cacheDuration: const Duration(minutes: 10),
      );

  static final IgcRepo _instance = IgcRepo._internal();
  static IgcRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, IGCRequestModel request) =>
      req.post(url: PApiUrls.igcLite, body: request.toJson());
}
