import 'package:fluffychat/features/subscription/models/subscription_state.dart';

/// Pure predicate for whether the in-app v2 cancel affordance should be shown
/// for the current subscription (I5). True iff a user-owned, cancelable
/// entitlement was selected AND the subscription is not already set to cancel at
/// period end AND we hold its `/status`-sourced `entitlementRef` (never a Stripe
/// id).
///
/// The nullable comparisons are deliberate: `cancelable`/`cancelAtPeriodEnd` are
/// null on the mobile/RC path, so a bare truthiness check would misfire —
/// `cancelable == true` is false when null, and `cancelAtPeriodEnd != true`
/// treats null as "not cancelling".
bool shouldShowV2Cancel(SubscriptionActive state) =>
    state.cancelable == true &&
    state.cancelAtPeriodEnd != true &&
    state.entitlementRef != null;
