import 'package:async/async.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/pangea/common/utils/async_repo_loader.dart';

class SubscriptionStatusProvider
    extends
        AsyncRepoLoader<SubscriptionStatusRequest, SubscriptionStatusResponse> {
  @override
  Future<Result<SubscriptionStatusResponse>> get(
    SubscriptionStatusRequest request,
  ) => SubscriptionStatusRepo.instance.get(request);
}
