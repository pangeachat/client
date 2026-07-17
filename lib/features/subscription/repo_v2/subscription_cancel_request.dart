import 'package:fluffychat/pangea/common/utils/base_request.dart';

class SubscriptionCancelRequest extends BaseRequest {
  final String userID;
  final String entitlementRef;
  SubscriptionCancelRequest({
    required this.userID,
    required this.entitlementRef,
  });

  @override
  String get storageKey => "subscription_cancel_${userID}_$entitlementRef";

  @override
  Map<String, dynamic> toJson() => {"entitlementRef": entitlementRef};
}
