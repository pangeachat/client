/// Client model for the Subscriptions-v2 `/subscription/checkout` response
/// (choreo `CheckoutResponse`, checkout_v2_schema.py).
///
/// - `created`  -> a fresh Stripe Checkout session (200 + sessionUrl)
/// - `reused`   -> the caller's already-open session (200 + sessionUrl); the
///   anti-double-tap path, never a second session
/// - `creating` -> another worker is mid-creation (202); poll after
///   [retryAfterSeconds]
class CheckoutResponse {
  final String status;
  final String? sessionUrl;
  final int? retryAfterSeconds;

  /// The promo code ACTUALLY on the returned session (the STORED code the
  /// server echoes back), or null when no discount is applied. On a `reused`
  /// open session the request's `promoCode` is IGNORED, so this — not the
  /// requested code — is the discount state the UI should reflect.
  final String? appliedPromoCode;

  const CheckoutResponse({
    required this.status,
    this.sessionUrl,
    this.retryAfterSeconds,
    this.appliedPromoCode,
  });

  /// A terminal, session-bearing response (`created` or `reused`).
  bool get isResolved => status == "created" || status == "reused";

  /// The in-progress state that drives the bounded poll (I3).
  bool get isCreating => status == "creating";

  factory CheckoutResponse.fromJson(Map<String, dynamic> json) =>
      CheckoutResponse(
        status: json['status'] as String,
        sessionUrl: json['sessionUrl'] as String?,
        retryAfterSeconds: (json['retryAfterSeconds'] as num?)?.toInt(),
        appliedPromoCode: json['appliedPromoCode'] as String?,
      );
}
