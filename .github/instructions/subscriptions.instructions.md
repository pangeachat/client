---
applyTo: "lib/features/subscription/**,lib/routes/settings/settings_subscription/**"
description: "Client subscription module — entitlement display from the choreographer, storefront-gated purchase steering, and in-app discount and management."
---

# Subscription Module — Client

Client-side subscription UI and purchase flow. For the cross-repo architecture — the web-only rationale, the entitlement model, and the platform policy — see [subscriptions.instructions.md](../../../.github/.github/instructions/subscriptions.instructions.md).

The client holds no payment state. It reads entitlement status from the choreographer, renders the purchase surface defined by the subscription design, and hands off to Stripe on the web for the actual payment.

## Entitlement state

[`SubscriptionController`](../../lib/features/subscription/controllers/subscription_controller.dart) resolves the user's status from the choreographer on startup — returning from web checkout must feel immediate, and server-side grants (seats, trials, comps) appear the same way. There is no RevenueCat SDK and no store-package merging: entitlement is a choreographer-served record that the app reflects, never unlocks. Paid features gate on `showSubscriptionGatedContent`; the paywall surfaces only when the user is unsubscribed outside the trial window and hasn't dismissed it.

## Purchase surface

Which purchase surface the client renders — the plans, prices, discount field, and whether checkout is offered — is defined by the org doc's [Platform policy](../../../.github/.github/instructions/subscriptions.instructions.md). The client renders that design; it does not decide it.

## Star backdrop

Every subscription surface — the settings paywall, the selected-plan page, the discount-code page, the billing history, and the onboarding free-trial step — paints the same star field behind its content through [`StarBackdrop`](../../lib/features/subscription/widgets/star_backdrop.dart). One shared widget, so the surfaces cannot drift apart. It is decorative and carries no semantics.

Content sits directly on the art. There is no panel behind it: an opaque panel covers the artwork the backdrop exists to show, which is what made the star and its two characters invisible (#8751). The blocks that need a reading surface already carry one — the PRO features box and the plan chips are framed cards with their own fill — and the art shows in the gaps between them.

Removing the panel is not enough on its own. The art is painted to cover the surface, which on a portrait screen scales it to the height exactly and so pins the character star to a fixed slice of the body whatever the screen size, while content height varies independently. So the surfaces keep the bottom of the body clear of content — `starBandFraction` — and the characters live there. The band is what makes the guarantee hold at every width, every scroll position and every text size rather than only on the screens someone happened to check. The onboarding free-trial step waives it, because its own layout already ends above the band.

The art's opacity is a contrast budget rather than a taste setting. Body text placed on the backdrop has to clear WCAG AA in both themes, and that fixes the ceiling at `starBackgroundOpacity`. Raising it to make the art bolder puts unreadable text back on the paywall.

Two kinds of content cannot clear that budget at any opacity, so they keep a surface of their own: the discount-code field, which the user types into, and the red and green status messages about an entered code. Those two colours are close to the surface's luminance whatever sits behind them.

## Purchase flow

Selecting a plan requests a checkout URL from the choreographer and opens it in the system browser ([`PaymentPageMixin`](../../lib/routes/settings/settings_subscription/payment_page_mixin.dart)). A `beganPayment` flag survives the round-trip, so returning to the app is recognized as a completed purchase and the entitlement refresh runs. The discount-code field validates the code server-side before checkout, so an error surfaces in the app and the code reaches Stripe pre-applied; the field appears only where the paywall may appear.

## Refreshing subscription info

Subscription info is initially fetched on session startup, and cached in the [SubscriptionController](../../lib/features/subscription/controllers/subscription_controller.dart) until explicitly reset. The client much refresh the cached subscription status info when it changes. All refreshes go through the SubscriptionController's [_updateCurrentSubscription](../../lib/features/subscription/controllers/subscription_controller.dart) function, which force-refreshes the cached value. The SubscriptionController calls this internally on startup ([_initialize](../../lib/features/subscription/controllers/subscription_controller.dart)), when a free trial is activated ([_activateNewUserTrial](../../lib/features/subscription/controllers/subscription_controller.dart)), and when the controller is explicitly reinitialized ([reinitialize](../../lib/features/subscription/controllers/subscription_controller.dart)). 

The settings page pulls subscription status from the SubscriptionController instead of fetching that info itself, and rebuilds automatically when updates are made in the SubscriptionController.

The client called reinitialize when:
1. A new user logs in ([PangeaController._onLogin](../../lib/pangea/common/controllers/pangea_controller.dart))
2. After a user creates an account, to trigger free trial activation
3. When a checkout request fails because the user already has a subscription. This is a fallback to account for the cache not being updated for a user with a subscription, so the UI allows them to start the checkout flow.
4. After a user cancels their subscription via the "Cancel" button in the [SubscriptionHistory](../../lib/routes/settings/settings_subscription/subscription_history.dart) page
5. When a refresh button is pressed in the errored-out subscription settings view

The client tracks potential subscription changes via the [SubscriptionManagementRepo](../../lib/features/subscription/repo_v2/subscription_management_repo.dart). It tracks if the user has started a payment and if the user has launched their billing portal, which can be used to cancel or restart subscriptions. The client uses with info the the [didChangeAppLifecycleState](../../lib/widgets/matrix.dart) override in [Matrix](../../lib/widgets/matrix.dart) to poll for refreshes to the subscription status when the user returns to the app. The polling has an exponential backoff, with a maximum of 5 calls to the status endpoint.

## Managing a subscription

Settings shows the current plan and billing history natively, cancels in the app, and opens a Stripe-hosted page only to change the payment card. This is account management, shown on every platform. Seat-sponsored learners (Group or Institution tier) see who sponsors their access in place of a paywall.
