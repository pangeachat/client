import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';

sealed class SubscriptionState {
  const SubscriptionState();

  factory SubscriptionState.fromSubscriptionStatus(
    SubscriptionStatusResponse status,
  ) => status.isActive
      ? SubscriptionActive(status)
      : SubscriptionInactive(status);
}

class SubscriptionLoading extends SubscriptionState {}

class SubscriptionActive extends SubscriptionState {
  final SubscriptionStatusResponse response;
  const SubscriptionActive(this.response);
}

class SubscriptionInactive extends SubscriptionState {
  final SubscriptionStatusResponse response;
  const SubscriptionInactive(this.response);
}

class SubscriptionError extends SubscriptionState {
  final Object error;

  SubscriptionError({required this.error});
}
