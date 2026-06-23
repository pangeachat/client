---
applyTo: "lib/pangea/subscription/**"
description: "Subscriptions v2 target design for the client — single web purchase flow, in-app discount codes, storefront-gated steering, choreographer-backed entitlement state."
---

# Subscriptions v2 — Client (Target Design)

**Status: target design, not implemented.** [subscriptions.instructions.md](subscriptions.instructions.md) describes production. Shared decisions, platform policy, and migration phases live in the [org-level v2 doc](../../../.github/instructions/subscriptions-v2.instructions.md) — read it first.

## UX

The paywall shows plans, prices, and a discount-code field. Entering a code shows the discounted price (or an inline error) without leaving the app. Subscribe opens Stripe checkout — same tab on web, the external browser on US mobile — and on return to the app the subscription is active. On non-US Android the paywall can name the web as the place to subscribe but carries no link; on non-US iOS it shows nothing at all. Institution-sponsored learners never see a paywall — they see who sponsors their access. Settings shows the current plan and billing history natively, cancels in-app, and opens a Stripe-hosted page only to change the payment card.

## Design

- **One purchase flow.** The v1 platform split (Web vs Mobile subscription classes, RC SDK initialization, store-package merging) collapses: every platform requests a checkout URL from the choreographer and opens it. Platform differences shrink to *where the URL opens* and *whether purchase UI may be shown at all*.
- **Entitlement state comes from the choreographer on every platform** — no RevenueCat SDK. Refresh on startup and app resume: returning from web checkout must feel immediate, and server-side grants (seats, trials, comps) appear the same way.
- **The client's purchase-UI work is the device + storefront-country presentation matrix** — what copy and links each surface shows. Legality of each tier lives in the org doc's Platform Policy; the client owns rendering it:

  | Surface | Copy | Link/CTA |
  |---|---|---|
  | Web | Full paywall: plans, prices, discount field | Checkout, same tab |
  | US mobile (iOS & Android) | Full paywall: plans, prices, discount field | Checkout, external browser |
  | Non-US Android | Names the web as the purchase channel | None |
  | Non-US iOS | None (at most: "subscriptions aren't available in this app") | None |

  Storefront country comes from the store APIs, never device locale. Tier boundaries will move (EU/Japan adoption, the Android settlement rollout) — the matrix is config, not scattered conditionals.
- **The discount code is validated server-side before checkout**, so errors surface in-app and the code reaches Stripe pre-applied. The code field appears only where the paywall itself may appear.
- **No code-redemption box** (rule and rationale: org doc Platform Policy). Seat and comp access arrives via server-side grants reflected at sign-in; the app reflects entitlement, it never unlocks it.
- **Legacy store subscribers** are comped server-side (see the org doc's Cutover phase) and look like any other entitled user to the client. The only special handling is a one-time prompt to cancel their store auto-renewal, deep-linking to the store's subscription settings.
