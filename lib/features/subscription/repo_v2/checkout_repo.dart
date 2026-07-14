import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';

class CheckoutRepo extends BaseRepo<CheckoutRequest, CheckoutResponse> {
  CheckoutRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: CheckoutResponse.fromJson,
        cacheDuration: const Duration(days: 1),
        timeout: Duration(seconds: 10),
      );

  static final CheckoutRepo _instance = CheckoutRepo._internal();
  static CheckoutRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, CheckoutRequest request) => req.post(
    url: PApiUrls.subscriptionCheckout,
    body: request.toJson(),
    enrichBody: false,
  );
}
