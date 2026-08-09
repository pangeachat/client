import 'package:async/async.dart';

import 'package:fluffychat/features/subscription/repo_v2/billing_portal_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/billing_portal_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/billing_portal_response.dart';
import 'package:fluffychat/pangea/common/utils/async_repo_loader.dart';

class BillingPortalProvider
    extends AsyncRepoLoader<BillingPortalRequest, BillingPortalResponse> {
  @override
  Future<Result<BillingPortalResponse>> get(BillingPortalRequest request) =>
      BillingPortalRepo.instance.get(request);
}
