import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import 'package:fluffychat/features/subscription/enums/subscription_duration_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';

class ProductsResponse extends BaseResponse {
  final List<ProductPlan> plans;
  final bool pricesLocalizedAtCheckout;
  final String? country;

  const ProductsResponse({
    required this.plans,
    required this.pricesLocalizedAtCheckout,
    this.country,
  });

  factory ProductsResponse.fromJson(Map<String, dynamic> json) {
    return ProductsResponse(
      plans: (json['plans'] as List<dynamic>? ?? [])
          .map((e) => ProductPlan.fromJson(e as Map<String, dynamic>))
          .toList(),
      pricesLocalizedAtCheckout:
          json['prices_localized_at_checkout'] as bool? ?? false,
      country: json['country'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'plans': plans.map((e) => e.toJson()).toList(),
      'prices_localized_at_checkout': pricesLocalizedAtCheckout,
      'country': country,
    };
  }
}

class ProductPlan {
  final String planId;
  final int amount;
  final String currency;
  final String interval;
  final int intervalCount;

  const ProductPlan({
    required this.planId,
    required this.amount,
    required this.currency,
    required this.interval,
    required this.intervalCount,
  });

  factory ProductPlan.fromJson(Map<String, dynamic> json) {
    return ProductPlan(
      planId: json['planId'] as String,
      amount: json['amount'] as int,
      currency: json['currency'] as String,
      interval: json['interval'] as String,
      intervalCount: json['interval_count'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'planId': planId,
      'amount': amount,
      'currency': currency,
      'interval': interval,
      'interval_count': intervalCount,
    };
  }

  SubscriptionDuration get duration =>
      SubscriptionDuration.values.firstWhereOrNull((d) => d.name == planId) ??
      SubscriptionDuration.month;

  String get priceDisplay {
    final updatedAmount = amount / 100;
    final symbol = NumberFormat().simpleCurrencySymbol(currency.toUpperCase());
    return "$symbol$updatedAmount";
  }

  String periodPriceDisplay(L10n l10n) =>
      duration.periodPriceDisplay(l10n, priceDisplay);
}
