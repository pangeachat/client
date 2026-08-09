import 'package:collection/collection.dart';

enum SubscriptionType {
  /// paid — an active, self-owned Stripe subscription the user directly pays for (a real paying customer).
  paid,

  /// individual — the RC/legacy label for a single learner's own subscription; in v2 it's the same thing as paid (self-pay, not group).
  individual,

  /// trial — the free 7-day trial, once per user ever (manual grant, no payment).
  trial,

  /// comp — complimentary/free access (promo, staff, RC promotional) — full access but not paying.
  comp,

  /// seat — access from a group/institution that bought them a seat (someone else pays).
  seat;

  static SubscriptionType? fromString(String value) {
    return SubscriptionType.values.firstWhereOrNull((e) => e.name == value);
  }

  bool get isBillable =>
      this == SubscriptionType.paid || this == SubscriptionType.individual;
}
