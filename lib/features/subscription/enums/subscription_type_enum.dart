enum SubscriptionType {
  paid,
  seat,
  comp,
  trial,
  individual,
  free;

  factory SubscriptionType.fromString(String value) {
    return SubscriptionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SubscriptionType.free,
    );
  }

  bool get isBillable =>
      this == SubscriptionType.paid || this == SubscriptionType.individual;
}
