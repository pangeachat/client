import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';

abstract class SubscriptionInfoManager {
  Future<SubscriptionState> getCurrentSubscriptionInfo();

  Future<void> submitSubscriptionChange(SubscriptionDetails subscription);
}
