---
applyTo: "lib/features/subscription/**,lib/routes/settings/settings_subscription/**"
description: "How the client reflects a learner's subscription, takes them to checkout, redeems discount codes and gift links, refreshes their status, and shows and manages their plan."
---

# Subscriptions — Client

The client shows a learner whether they have paid AI access, takes them to checkout where the platform allows it, and lets them manage their plan. It holds no payment state: it reflects what the choreographer reports and hands payment to Stripe on the web. The cross-repo design (why purchase is web-only, the entitlement model, platform policy) is in [subscriptions.instructions.md](../../../.github/.github/instructions/subscriptions.instructions.md).

## The experience

1. When the app starts, it checks the learner's subscription and starts a free trial for a new learner in their trial window.
2. An unsubscribed learner outside the trial window finds paid features locked, and sees the paywall unless they have dismissed it.
3. They choose a plan, with a discount code if they have one, and pay on Stripe's checkout page.
4. Back in the app, the purchase is picked up at once.

## Where entitlement comes from

Entitlement is a record the choreographer serves; the app reflects it and never unlocks anything itself. There is no in-app purchase. Server-side grants (seats, trials, comps) show up like a purchase. Which plans, prices and checkout a device shows is the org doc's [Platform policy](../../../.github/.github/instructions/subscriptions.instructions.md#platform-policy); the client renders it and does not decide it.

## Checkout and discount codes

Checkout opens in the system browser, and returning counts as a purchase once the subscription shows up.

A discount code is checked first, so a bad code shows its error in the app and a good one reaches Stripe already applied. The button to the discount-code page appears only where the paywall may appear, and never on iOS, where App Review rejected it.

## Gift links

A promo code can arrive as a link, which opens the discount page with the code, on web and in the app, iOS included, and a signed-out visitor's link survives login, signup and onboarding ([routing.instructions.md § A signed-out visitor's destination](routing.instructions.md#a-signed-out-visitors-destination)).

Signed in, the page checks the code at once and opens on the plans with the discount applied. A code that fails (invalid, expired, or already used, since each works once) shows the usual error with the field on every platform, so the learner can correct it. The code is never logged or reported: analytics and error reports name the page without it ([google-analytics.instructions.md](google-analytics.instructions.md)).

## When status refreshes

The app fetches status at startup and keeps it until something may change it. It fetches again when a learner logs in; when a new account is created, so the free trial can start; when checkout is refused because the learner already has a subscription (the app's copy was out of date); when the learner cancels; and when the learner taps refresh after the page failed to load. After a return from checkout or the Stripe billing page, it checks a few times, waiting longer each time. Settings always shows the current copy.

## Managing a subscription

Settings shows the plan and billing history, cancels in the app, and opens a Stripe-hosted page only to change the payment card. This is account management, shown on every platform. Seat-sponsored learners (Group or Institution tier) see who sponsors their access in place of a paywall.

## The plan card

The plan card, on Subscription Management and its Manage page, tells the learner what their next payment costs, until when, and what happens after. With a discount, the full price is struck through beside what they will pay, and a payment that costs nothing shows as free. The line beneath changes only for what will change: when a discount ends and the full price starts; when the plan will end because no card is on file, with a prompt to add one; or, after a renewal payment fails, when the grace period ends, shown as an error. Access lasts until then unless a payment goes through. A cancelled plan shows its end date. Without discount or card information, it shows the plain renewal date rather than guess.

For each subscription the choreographer sends the discount (a percentage or amount off), the date of the first full-price payment, and whether a card is on file, so the app works out no billing dates itself.

## Star background

The subscription pages show the star art full bleed. It is decorative and only cards cover it, so the stars show between and around them; a solid panel blanking out the middle is a bug. No text sits directly on the art: every line, heading, error, notice and field sits on a card or its own background.

## Open questions

1. Paywall in the trial window. This doc hides the paywall during the trial window, but the code may show it to an unsubscribed learner then. Which is intended?
2. Sponsor display. No display of a seat-sponsored learner's sponsor was found in the client. Planned or dropped?
