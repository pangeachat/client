import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class SubscriptionCancelRepo
    extends BaseRepo<SubscriptionCancelRequest, SubscriptionCancelResponse> {
  SubscriptionCancelRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: SubscriptionCancelResponse.fromJson,
        cacheDuration: Duration(seconds: 10),
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

  Future<Result<SubscriptionCancelResponse>> cancelSubscription(
    SubscriptionCancelRequest request,
  ) async {
    const maxAttempts = 5;
    Object? lastError;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final result = await instance.get(request, forceRefresh: attempt > 0);

      final response = result.result;
      if (response != null) {
        return Result.value(response);
      }

      lastError = result.error;
      if (attempt < maxAttempts - 1) {
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }

    return Result.error(lastError ?? "Failed to cancel subscription");
  }
}
