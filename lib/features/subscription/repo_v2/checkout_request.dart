import 'package:fluffychat/pangea/common/utils/base_request.dart';

class CheckoutRequest extends BaseRequest {
  final String userID;
  final String planId;
  final String? promoCode;

  CheckoutRequest({required this.userID, required this.planId, this.promoCode});

  @override
  String get storageKey => "checkout_${userID}_${planId}_$promoCode";

  @override
  Map<String, dynamic> toJson() {
    return {'planId': planId, if (promoCode != null) 'promoCode': promoCode};
  }

  /// The code stays out of error telemetry (#9281); whether one was sent is
  /// still useful when a checkout fails.
  @override
  Map<String, dynamic> toReportData() => {
    'planId': planId,
    'hasPromoCode': promoCode != null,
  };
}
