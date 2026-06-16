import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/utils/subscription_duration_enum.dart';

class SubscriptionDetails {
  final double price;
  final SubscriptionDuration? duration;
  final String? appId;
  final String id;
  final bool isVisible;
  final Package? package;
  final String? localizedPrice;

  SubscriptionDetails({
    required this.price,
    required this.id,
    this.duration,
    this.package,
    this.appId,
    this.isVisible = true,
    this.localizedPrice,
  });

  bool get isTrial => appId == "trial";

  String displayPrice(BuildContext context) => isTrial || price <= 0
      ? L10n.of(context).freeTrial
      : localizedPrice ?? "\$${price.toStringAsFixed(2)}";

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
  }) => SubscriptionDetails(
    price: price ?? this.price,
    duration: duration ?? this.duration,
    appId: appId ?? this.appId,
    id: id ?? this.id,
    isVisible: isVisible ?? this.isVisible,
    package: package ?? this.package,
    localizedPrice: localizedPrice ?? this.localizedPrice,
  );

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['price'] = price;
    data['id'] = id;
    data['duration'] = duration?.value;
    data['appId'] = appId;
    data['is_visible'] = isVisible;
    return data;
  }

  factory SubscriptionDetails.fromJson(Map<String, dynamic> json) {
    return SubscriptionDetails(
      price: json['price'],
      duration: SubscriptionDuration.values.firstWhereOrNull(
        (duration) => duration.value == json['duration'],
      ),
      id: json['id'],
      appId: json['appId'],
      isVisible: json['is_visible'] ?? true,
    );
  }
}
