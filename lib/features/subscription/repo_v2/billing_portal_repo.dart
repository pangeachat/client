import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/billing_portal_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/billing_portal_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';

class BillingPortalRepo
    extends BaseRepo<BillingPortalRequest, BillingPortalResponse> {
  BillingPortalRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: BillingPortalResponse.fromJson,
        cacheDuration: Duration(minutes: 10),
        timeout: Duration(seconds: 10),
      );

  static final BillingPortalRepo _instance = BillingPortalRepo._internal();
  static BillingPortalRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, BillingPortalRequest _) =>
      req.get(url: PApiUrls.billingPortal);
}
