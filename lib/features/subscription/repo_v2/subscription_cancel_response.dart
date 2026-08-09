import 'package:fluffychat/pangea/common/utils/base_response.dart';

class SubscriptionCancelResponse extends BaseResponse {
  final String status;
  final String entitlementRef;

  const SubscriptionCancelResponse({
    required this.status,
    required this.entitlementRef,
  });

  @override
  Map<String, dynamic> toJson() => {
    "status": status,
    "entitlementRef": entitlementRef,
  };

  factory SubscriptionCancelResponse.fromJson(Map<String, dynamic> json) =>
      SubscriptionCancelResponse(
        status: json["status"] as String,
        entitlementRef: json['entitlementRef'] as String? ?? "",
      );
}
