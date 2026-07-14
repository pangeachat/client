enum SubscriptionStatus {
  active,
  canceled,
  expired,
  trialing;

  factory SubscriptionStatus.fromString(String value) {
    return SubscriptionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SubscriptionStatus.expired,
    );
  }
}
