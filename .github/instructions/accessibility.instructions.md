---
applyTo: "lib/pangea/**,lib/pages/**,lib/widgets/**"
description: "Accessibility design intent for the client — what audit-ready means, why a canvas app needs explicit naming, and what automated tests do and don't cover."
---

# Accessibility — Design Intent

We build for screen-reader, keyboard, and low-vision users as a first-class requirement, not a retrofit. Institutional buyers and the WL360 research studies treat accessibility as a procurement gate, so "audit-ready" (WCAG 2.1 AA) is a product target, not a nice-to-have.

## The one fact that shapes everything

The app renders to a single opaque `<canvas>`. Unlike a normal web page, **nothing is accessible by default** — a button, a field, an image is invisible to assistive tech until we explicitly give it a name. Accessibility here is an act of authoring, performed element by element as the UI is built, not a setting we switch on later. The mechanical per-widget naming rules live in [playwright-testing.instructions.md § Widget testability](playwright-testing.instructions.md#widget-testability--non-negotiable); honor them as you build, because the same omission that breaks a test breaks a real screen-reader user.

## What "audit-ready" means

An auditor checks three independent things. All three must hold; passing one does not imply the others.

- **Operable by screen reader** — every interactive element announces what it is and what it does; images are either described or marked decorative; reading order makes sense.
- **Operable by keyboard alone** — every action is reachable and triggerable without a mouse, focus is always visible, and focus never gets trapped.
- **Usable by low vision** — sufficient color contrast, text that survives zoom/resize, and nothing conveyed by color alone.

## Don't mistake green tests for audit-ready

Our automated axe suite is a **regression guard for flows we've already labeled**, not a conformance measure. It runs against the semantics overlay only, so by design it cannot see:

- **Color contrast and visual layout** — pixels inside the canvas are opaque to it.
- **Real keyboard operability and focus visibility** — presence of a name is not proof the app is operable.
- **Actual screen-reader behavior** — a named element is not proof VoiceOver/TalkBack/NVDA announce it correctly.
- **Mobile** — iOS/Android, where most users are, are out of scope until Patrol lands.

These gaps close only through **manual passes**: a real screen reader, keyboard-only navigation, and a contrast/zoom review. Treat the automated suite as ~a quarter of the work and the manual passes as the rest.

## Responsibility

Accessibility is owned by whoever builds or changes the UI, in the same change — not deferred to a later test-writing or audit pass. New interactive surfaces ship with names; new flows get a manual screen-reader sanity check. The living coverage backlog is [`e2e/web-and-accessibility-next-steps.md`](../../e2e/web-and-accessibility-next-steps.md).
