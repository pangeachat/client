import 'package:fluffychat/pangea/common/utils/base_request.dart';

class SubscriptionCancelRequest extends BaseRequest {
  final String entitlementRef;
  SubscriptionCancelRequest({required this.entitlementRef});

  @override
  String get storageKey => "subscription_cancel_$entitlementRef";

  @override
  Map<String, dynamic> toJson() => {"entitlementRef": entitlementRef};
}
