import 'package:collection/collection.dart';

enum SubscriptionType {
  /// paid — an active, self-owned Stripe subscription the user directly pays for (a real paying customer).
  paid,

  /// trial — the free 7-day trial, once per user ever (manual grant, no payment).
  trial,

  /// comp — complimentary/free access (promo, staff) — full access but not paying.
  comp,

  /// seat — access from a group/institution that bought them a seat (someone else pays).
  seat;

  static SubscriptionType? fromString(String value) {
    return SubscriptionType.values.firstWhereOrNull((e) => e.name == value);
  }

  bool get isBillable => this == SubscriptionType.paid;
}
