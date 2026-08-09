import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/free_trial_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/free_trial_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';

class FreeTrialRepo extends BaseRepo<FreeTrialRequest, FreeTrialResponse> {
  FreeTrialRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: FreeTrialResponse.fromJson,
        cacheDuration: Duration(seconds: 10),
        timeout: Duration(seconds: 10),
      );

  static final FreeTrialRepo _instance = FreeTrialRepo._internal();
  static FreeTrialRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, FreeTrialRequest _) =>
      req.get(url: PApiUrls.freeTrial);
}
