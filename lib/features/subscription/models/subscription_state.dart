sealed class SubscriptionState {}

class SubscriptionLoading extends SubscriptionState {}

class SubscriptionActive extends SubscriptionState {
  final String subscriptionId;
  final DateTime? expirationDate;
  final DateTime? unsubscribeDetectedAt;

  SubscriptionActive({
    required this.subscriptionId,
    this.expirationDate,
    this.unsubscribeDetectedAt,
  });
}

class SubscriptionInactive extends SubscriptionState {}

class SubscriptionError extends SubscriptionState {
  final Object error;

  SubscriptionError({required this.error});
}
