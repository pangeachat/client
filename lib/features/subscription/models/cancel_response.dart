/// Client model for the Subscriptions-v2 `/subscription/cancel` response
/// (choreo `CancelSubscriptionResponse`, status_v2_schema.py). The subscription
/// is set to cancel at the end of the current paid period; access continues
/// until then. The client refetches `/subscription/status` to observe
/// `cancel_at_period_end` once the webhook reflects it.
class CancelResponse {
  /// Always "cancel_at_period_end" on success.
  final String status;
  final String entitlementRef;

  const CancelResponse({required this.status, required this.entitlementRef});

  factory CancelResponse.fromJson(Map<String, dynamic> json) => CancelResponse(
    status: json['status'] as String? ?? "",
    entitlementRef: json['entitlementRef'] as String? ?? "",
  );
}
