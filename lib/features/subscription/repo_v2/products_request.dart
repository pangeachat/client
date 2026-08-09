import 'package:fluffychat/pangea/common/utils/base_request.dart';

class ProductsRequest extends BaseRequest {
  final String userID;
  ProductsRequest({required this.userID});

  @override
  String get storageKey => "subscription_products_$userID";

  @override
  Map<String, dynamic> toJson() => {};
}
