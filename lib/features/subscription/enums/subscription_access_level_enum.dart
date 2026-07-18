enum SubscriptionAccessLevel {
  full,
  none;

  factory SubscriptionAccessLevel.fromString(String value) {
    return SubscriptionAccessLevel.values.firstWhere((v) => v.name == value);
  }
}
