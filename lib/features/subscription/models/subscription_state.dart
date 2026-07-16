import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';

sealed class SubscriptionState {
  const SubscriptionState();

  factory SubscriptionState.fromSubscriptionStatus(
    SubscriptionStatusResponse status,
  ) {
    final winning = status.winning;
    if (status.accessLevel != SubscriptionAccessLevel.full || winning == null) {
      return SubscriptionInactive(status);
    }
    return SubscriptionActive(status);
  }
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
