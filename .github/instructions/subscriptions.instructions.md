---
applyTo: "lib/features/subscription/**,lib/routes/settings/settings_subscription/**"
description: "Client subscription module — entitlement display from the choreographer, storefront-gated purchase steering, and in-app discount and management."
---

# Subscription Module — Client

Client-side subscription UI and purchase flow. For the cross-repo architecture — the web-only rationale, the entitlement model, and the platform policy — see [subscriptions.instructions.md](../../../.github/.github/instructions/subscriptions.instructions.md).

The client holds no payment state. It reads entitlement status from the choreographer, renders the right purchase surface for the device's storefront, and hands off to Stripe on the web for the actual payment.

## Entitlement state

[`SubscriptionController`](../../lib/features/subscription/controllers/subscription_controller.dart) resolves the user's status from the choreographer on startup and on app resume — returning from web checkout must feel immediate, and server-side grants (seats, trials, comps) appear the same way. There is no RevenueCat SDK and no store-package merging: entitlement is a choreographer-served record that the app reflects, never unlocks. Paid features gate on `showSubscriptionGatedContent`; the paywall surfaces only when the user is unsubscribed outside the trial window and hasn't dismissed it.

## Purchase surface

What the paywall may show is gated by storefront and device, because the legality of purchase steering differs per store — the rules and their rationale live in the org doc's Platform policy. The client owns rendering the matrix; it does not decide the law.

| Surface | Paywall (plans, prices, discount field) | Checkout |
|---|---|---|
| Web | Full | Redirect, same tab |
| US mobile (iOS & Android) | Full | System browser |
| Non-US Android | Names the web as the purchase channel, no link | None |
| Non-US iOS | Nothing (at most "Subscriptions can't be purchased in the app") | None |

Storefront country comes from the store APIs, never device locale. The matrix is configuration — tier boundaries move as markets and settlements change.

## Purchase flow

Selecting a plan requests a checkout URL from the choreographer and opens it in the system browser ([`PaymentPageMixin`](../../lib/routes/settings/settings_subscription/payment_page_mixin.dart)). A `beganPayment` flag survives the round-trip, so returning to the app is recognized as a completed purchase and the entitlement refresh runs. The discount-code field validates the code server-side before checkout, so an error surfaces in the app and the code reaches Stripe pre-applied; the field appears only where the paywall may appear.

## Managing a subscription

Settings shows the current plan and billing history natively, cancels in the app, and opens a Stripe-hosted page only to change the payment card. This is account management, shown on every platform. Institution-sponsored learners see who sponsors their access in place of a paywall.
