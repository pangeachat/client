import 'package:fluffychat/features/subscription/repo/products_request.dart';
import 'package:fluffychat/features/subscription/repo/products_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:http/http.dart';

class ProductsRepo extends BaseRepo<ProductsRequest, ProductsResponse> {
  ProductsRepo._internal()
    : super(
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
