import 'package:fluffychat/pangea/common/utils/base_request.dart';

class CheckoutRequest extends BaseRequest {
  final String planId;
  final String? promoCode;

  CheckoutRequest({required this.planId, this.promoCode});

  @override
  String get storageKey => "checkout_${planId}_$promoCode";

  @override
  Map<String, dynamic> toJson() {
    return {'planId': planId, if (promoCode != null) 'promoCode': promoCode};
  }
}
