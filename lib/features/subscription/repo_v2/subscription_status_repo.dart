import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

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

  Future<SubscriptionStatusResponse?> pollSubscriptionStatus(
    SubscriptionStatusRequest request,
    bool Function(SubscriptionStatusResponse) pollResponse,
  ) async {
    const maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final result = await instance.get(request, forceRefresh: true);
      final response = result.result;
      if (response != null && pollResponse(response)) {
        return response;
      }

      if (attempt < maxAttempts - 1) {
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    return null;
  }
}
