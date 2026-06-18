import 'package:fluffychat/pangea/subscription/models/subscription_details.dart';
import 'package:fluffychat/pangea/subscription/models/subscription_state.dart';

abstract class SubscriptionInfoManager {
  Future<SubscriptionState> getCurrentSubscriptionInfo();

  Future<void> submitSubscriptionChange(SubscriptionDetails subscription);
}
