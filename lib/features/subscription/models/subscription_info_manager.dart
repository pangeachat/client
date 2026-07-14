import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';

abstract class SubscriptionInfoManager {
  /// [stripeAppId] is the resolved `/subscription_app_ids` `stripeId`, threaded
  /// through only for the web v2 status mapper (D7). Additive + defaulted: the
  /// mobile/RC implementation ignores it, so its behavior is unchanged.
  Future<SubscriptionState> getCurrentSubscriptionInfo({String? stripeAppId});

  Future<void> submitSubscriptionChange(SubscriptionDetails subscription);
}
