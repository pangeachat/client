import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';

class ProductsRepo extends BaseRepo<ProductsRequest, ProductsResponse> {
  ProductsRepo._internal()
    : super(
        cache: PersistentRepoCache('subscription_products_storage'),
        responseFromJson: ProductsResponse.fromJson,
        cacheDuration: const Duration(days: 1),
        timeout: Duration(seconds: 10),
      );

  static final ProductsRepo _instance = ProductsRepo._internal();
  static ProductsRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, ProductsRequest _) =>
      req.get(url: PApiUrls.subscriptionProducts);
}
