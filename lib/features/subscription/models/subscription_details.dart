import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fluffychat/features/subscription/utils/subscription_duration_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';

class SubscriptionDetails {
  final double price;
  final SubscriptionDuration? duration;
  final String? appId;
  final String id;
  final bool isVisible;
  final Package? package;
  final String? localizedPrice;

  /// ISO currency code (lowercase, e.g. "usd") for the v2 web path (D5). Null on
  /// the mobile/RC path, where display stays on `localizedPrice`/`$`.
  final String? currency;

  SubscriptionDetails({
    required this.price,
    required this.id,
    this.duration,
    this.package,
    this.appId,
    this.isVisible = true,
    this.localizedPrice,
    this.currency,
  });

  bool get isTrial => appId == "trial";

  /// Context-free price string for a non-trial, priced product. Kept separate
  /// from [displayPrice] so the currency logic is unit-testable without a
  /// BuildContext/L10n. Precedence: an RC store-localized string wins; then a
  /// currency-aware format (v2 web, D5); then today's plain `$` fallback.
  ///
  /// When [currency] is null (mobile/RC path) this collapses to the exact
  /// prior expression `localizedPrice ?? "$price"`, so mobile output is
  /// byte-for-byte unchanged.
  String formattedPrice() {
    final localized = localizedPrice;
    if (localized != null) return localized;
    final currencyCode = currency;
    if (currencyCode != null) {
      return NumberFormat.simpleCurrency(
        name: currencyCode.toUpperCase(),
      ).format(price);
    }
    return "\$${price.toStringAsFixed(2)}";
  }

  String displayPrice(BuildContext context) =>
      isTrial || price <= 0 ? L10n.of(context).freeTrial : formattedPrice();

  String displayName(BuildContext context) {
    if (isTrial) {
      return L10n.of(context).oneWeekTrial;
    }
    switch (duration) {
      case (SubscriptionDuration.month):
        return L10n.of(context).monthlySubscription;
      case (SubscriptionDuration.year):
        return L10n.of(context).yearlySubscription;
      default:
        return L10n.of(context).defaultSubscription;
    }
  }

  SubscriptionDetails copyWith({
    double? price,
    SubscriptionDuration? duration,
    String? appId,
    String? id,
    bool? isVisible,
    Package? package,
    String? localizedPrice,
    String? currency,
  }) => SubscriptionDetails(
    price: price ?? this.price,
    duration: duration ?? this.duration,
    appId: appId ?? this.appId,
    id: id ?? this.id,
    isVisible: isVisible ?? this.isVisible,
    package: package ?? this.package,
    localizedPrice: localizedPrice ?? this.localizedPrice,
    currency: currency ?? this.currency,
  );

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['price'] = price;
    data['id'] = id;
    data['duration'] = duration?.name;
    data['appId'] = appId;
    data['is_visible'] = isVisible;
    // Omit `currency` entirely when null so the mobile/RC serialized JSON is
    // byte-for-byte identical to today; only the v2 web path (currency != null)
    // adds the key.
    if (currency != null) {
      data['currency'] = currency;
    }
    return data;
  }

  factory SubscriptionDetails.fromJson(Map<String, dynamic> json) {
    return SubscriptionDetails(
      price: json['price'],
      duration: SubscriptionDuration.values.firstWhereOrNull(
        (duration) => duration.name == json['duration'],
      ),
      id: json['id'],
      appId: json['appId'],
      isVisible: json['is_visible'] ?? true,
      currency: json['currency'],
    );
  }
}
