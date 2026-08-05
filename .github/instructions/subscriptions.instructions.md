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

Settings shows the current plan and billing history natively, cancels in the app, and opens a Stripe-hosted page only to change the payment card. This is account management, shown on every platform. Institution-sponsored learners see who sponsors their access in place of a paywall.
