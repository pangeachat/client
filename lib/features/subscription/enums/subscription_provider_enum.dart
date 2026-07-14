enum SubscriptionProvider {
  stripe,
  rc;

  factory SubscriptionProvider.fromString(String value) {
    return SubscriptionProvider.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SubscriptionProvider.stripe,
    );
  }
}
