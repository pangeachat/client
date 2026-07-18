import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';

class SubscriptionStatusRepo
    extends BaseRepo<SubscriptionStatusRequest, SubscriptionStatusResponse> {
  SubscriptionStatusRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: SubscriptionStatusResponse.fromJson,
        cacheDuration: Duration(minutes: 10),
        timeout: Duration(seconds: 10),
      );

  static final SubscriptionStatusRepo _instance =
      SubscriptionStatusRepo._internal();

  static SubscriptionStatusRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, SubscriptionStatusRequest _) =>
      req.get(url: PApiUrls.subscriptionStatus);
}
