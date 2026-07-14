class SubscriptionConstants {
  static const String starBackground = "Background+Star+with+characters.png";
}

/// The synthesized catalog id + appId sentinel for the Subscriptions-v2 web
/// trial (D3/D7). A trial has no Stripe catalog plan, so the client uses this
/// stable value both as the synthesized trial [SubscriptionDetails] id AND as
/// the active-trial `subscriptionId` produced by `mapStatusV2ToState`, so the
/// controller `subscription` getter resolves the trial tile (which keys off
/// `appId == "trial"`). Matches the RC catalog's existing trial appId.
const String kV2TrialId = "trial";

/// Fallback Stripe app-id for the v2 web path used when
/// `/subscription_app_ids` has not yet resolved a `stripeId`. Keeps the
/// status/products mappers producing a stable, non-null appId so management
/// degrades gracefully rather than stranding on a null id.
const String kStripeAppIdFallback = "stripe";
