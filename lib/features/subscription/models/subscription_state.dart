sealed class SubscriptionState {}

class SubscriptionLoading extends SubscriptionState {}

class SubscriptionActive extends SubscriptionState {
  final String subscriptionId;
  final DateTime? expirationDate;
  final DateTime? unsubscribeDetectedAt;

  /// Subscriptions-v2 additive fields (I6). All null/false on the mobile/RC
  /// path, which never sets them — so mobile behavior is unchanged. They are
  /// populated only by `mapStatusV2ToState` on the web v2 path.

  /// The `/status` entitlement ref to pass to `/cancel`; null unless a
  /// user-owned, cancelable entitlement was selected (I5/I10). NEVER a Stripe
  /// id.
  final String? entitlementRef;

  /// Whether an in-app cancel is available for the selected entitlement.
  final bool? cancelable;

  /// Whether the winning subscription is already set to end at the period end
  /// (mirrors the winning summary's `cancel_at_period_end`).
  final bool? cancelAtPeriodEnd;

  /// v2 promo signal: `!isV2PaidType(winning.type)` (I11) — true for granted
  /// (seat/comp) or trial access, false for billable paid/individual. Nullable
  /// so the RC-path getter can fall back to `id.startsWith("rc_promo")` when
  /// this is null.
  final bool? isPromotional;

  /// v2 trial signal: `winning.type == "trial"`. Lets the wiring layer render
  /// the trial tile (`appId == "trial"`, no cancel) and distinguish a trial
  /// from a comp/seat (both of which are also promotional). False on mobile/RC.
  final bool isTrial;

  SubscriptionActive({
    required this.subscriptionId,
    this.expirationDate,
    this.unsubscribeDetectedAt,
    this.entitlementRef,
    this.cancelable,
    this.cancelAtPeriodEnd,
    this.isPromotional,
    this.isTrial = false,
  });
}

class SubscriptionInactive extends SubscriptionState {}

class SubscriptionError extends SubscriptionState {
  final Object error;

  SubscriptionError({required this.error});
}
