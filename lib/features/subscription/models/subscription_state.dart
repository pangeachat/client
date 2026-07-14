sealed class SubscriptionState {}

class SubscriptionLoading extends SubscriptionState {}

class SubscriptionActive extends SubscriptionState {}

class SubscriptionInactive extends SubscriptionState {}

class SubscriptionError extends SubscriptionState {
  final Object error;

  SubscriptionError({required this.error});
}
