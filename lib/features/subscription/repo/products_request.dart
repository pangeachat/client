import 'package:fluffychat/pangea/common/utils/base_request.dart';

class ProductsRequest extends BaseRequest {
  @override
  String get storageKey => "subscription_products";

  @override
  Map<String, dynamic> toJson() => {};
}
