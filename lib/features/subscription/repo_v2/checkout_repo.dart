import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/checkout_error_response_parser.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class CheckoutRepo extends BaseRepo<CheckoutRequest, CheckoutResponse> {
  CheckoutRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: CheckoutResponse.fromJson,
        cacheDuration: Duration(seconds: 10),
        timeout: Duration(seconds: 10),
        errorResponseParser: CheckoutErrorResponseParser(),
      );

  static final CheckoutRepo _instance = CheckoutRepo._internal();
  static CheckoutRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, CheckoutRequest request) => req.post(
    url: PApiUrls.subscriptionCheckout,
    body: request.toJson(),
    enrichBody: false,
    errorResponseParser: errorResponseParser,
  );

  Future<Result<String>> getPaymentLink(CheckoutRequest request) async {
    CheckoutResponse? response;

    for (int attempt = 0; attempt < 5; attempt++) {
      final result = await instance.get(request, forceRefresh: attempt > 0);

      response = result.result;
      if (response == null) {
        return Result.error(result.error ?? "Failed to checkout");
      }

      if (response.sessionUrl != null) {
        return Result.value(response.sessionUrl!);
      }

      if (!response.isCreating) {
        break;
      }

      await Future.delayed(Duration(seconds: response.retryAfterSeconds ?? 2));
    }

    return Result.error("Failed to checkout");
  }
}
