enum SubscriptionDuration {
  month,
  year;

  String get value => this == SubscriptionDuration.month ? "month" : "year";
}
