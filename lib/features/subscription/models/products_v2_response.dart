import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/utils/subscription_duration_enum.dart';

/// A single plan from the Subscriptions-v2 `/subscription/products` storefront
/// (choreo `ProductPlanV2`). `amount` is the SERVER-OWNED base price in the
/// currency's minor units (999 == 9.99); `currency` is the lowercase ISO code
/// (Stripe convention). The Stripe `priceId` is deliberately never exposed —
/// the client subscribes by [planId].
class ProductV2 {
  final String planId;
  final int amount;
  final String currency;
  final String interval;
  final int intervalCount;

  const ProductV2({
    required this.planId,
    required this.amount,
    required this.currency,
    required this.interval,
    this.intervalCount = 1,
  });

  factory ProductV2.fromJson(Map<String, dynamic> json) => ProductV2(
    planId: json['planId'] as String,
    amount: (json['amount'] as num).toInt(),
    currency: json['currency'] as String,
    interval: json['interval'] as String,
    intervalCount: (json['interval_count'] as num?)?.toInt() ?? 1,
  );
}

/// The `/subscription/products` response envelope (choreo `ProductsV2Response`).
class ProductsV2Response {
  final List<ProductV2> plans;

  /// The displayed `amount`/`currency` are the server-owned BASE price; Stripe
  /// Adaptive Pricing localizes the buyer's actual charge at checkout. This
  /// flag (default true) tells the client the shown price is the base.
  final bool pricesLocalizedAtCheckout;

  /// Display-only echo of the `X-Storefront-Country` hint; never selects a
  /// price.
  final String? country;

  const ProductsV2Response({
    required this.plans,
    this.pricesLocalizedAtCheckout = true,
    this.country,
  });

  factory ProductsV2Response.fromJson(Map<String, dynamic> json) {
    final rawPlans = (json['plans'] as List<dynamic>?) ?? const <dynamic>[];
    return ProductsV2Response(
      plans: rawPlans
          .map((e) => ProductV2.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      pricesLocalizedAtCheckout:
          json['prices_localized_at_checkout'] as bool? ?? true,
      country: json['country'] as String?,
    );
  }
}

/// Explicit `planId -> duration` whitelist (I4). Unknown ids THROW rather than
/// silently degrade, so a new/renamed backend plan can never map to a null
/// duration that would strand the web checkout (which needs a duration to
/// resolve a planId).
const Map<String, SubscriptionDuration> kPlanIdToDuration =
    <String, SubscriptionDuration>{
      "month": SubscriptionDuration.month,
      "year": SubscriptionDuration.year,
    };

/// Thrown when a v2 plan id is outside the [kPlanIdToDuration] whitelist (I4).
class UnknownPlanIdException implements Exception {
  final String planId;
  const UnknownPlanIdException(this.planId);

  @override
  String toString() =>
      'UnknownPlanIdException: "$planId" is not a known v2 plan id '
      '(expected one of ${kPlanIdToDuration.keys.toList()})';
}

/// Pure mapper: a v2 [ProductV2] -> the existing [SubscriptionDetails] shape so
/// a Stripe web plan renders through the same RC-coupled getters (D7).
///
/// - `id = planId` (so the `subscription` getter resolves by id containment)
/// - `price = amount / 100.0`
/// - `currency` carried through for currency-aware display (D5)
/// - `duration` via the [kPlanIdToDuration] whitelist; unknown id THROWS (I4)
/// - `appId = stripeAppId` (so management getters treat it as a web purchase)
/// - `isVisible = true`
SubscriptionDetails productV2ToSubscriptionDetails(
  ProductV2 product, {
  required String stripeAppId,
}) {
  final duration = kPlanIdToDuration[product.planId];
  if (duration == null) {
    throw UnknownPlanIdException(product.planId);
  }
  return SubscriptionDetails(
    id: product.planId,
    price: product.amount / 100.0,
    currency: product.currency,
    duration: duration,
    appId: stripeAppId,
    isVisible: true,
  );
}
