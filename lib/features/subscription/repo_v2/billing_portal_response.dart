import 'package:fluffychat/pangea/common/utils/base_response.dart';

class BillingPortalResponse extends BaseResponse {
  /// The Stripe-hosted billing portal session, or null when the user has no
  /// billing account to manage — see [BillingPortalResponse.noBillingAccount].
  final String? url;

  BillingPortalResponse({required this.url});

  /// The successful "there is nothing to manage" value. The portal exists only
  /// to change a saved payment card (subscriptions.instructions.md), so a user
  /// without a Stripe customer has no portal — an expected state, not a
  /// failure.
  factory BillingPortalResponse.noBillingAccount() =>
      BillingPortalResponse(url: null);

  bool get hasBillingAccount => url != null;

  @override
  Map<String, dynamic> toJson() => {"url": url};

  factory BillingPortalResponse.fromJson(Map<String, dynamic> json) =>
      BillingPortalResponse(url: json["url"] as String?);
}
