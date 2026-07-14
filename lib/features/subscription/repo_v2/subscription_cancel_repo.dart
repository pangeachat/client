import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';

class SubscriptionCancelRepo
    extends BaseRepo<SubscriptionCancelRequest, SubscriptionCancelResponse> {
  SubscriptionCancelRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: SubscriptionCancelResponse.fromJson,
        cacheDuration: const Duration(days: 1),
        timeout: Duration(seconds: 10),
      );

  static final SubscriptionCancelRepo _instance =
      SubscriptionCancelRepo._internal();
  static SubscriptionCancelRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, SubscriptionCancelRequest request) =>
      req.post(
        url: PApiUrls.subscriptionCancel,
        body: request.toJson(),
        enrichBody: false,
      );
}
