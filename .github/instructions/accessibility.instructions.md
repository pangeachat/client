---
applyTo: "lib/pangea/**,lib/routes/**,lib/widgets/**,e2e/**"
description: "Accessibility design intent and audit-coverage strategy for the client — canvas-as-authoring, what axe can and cannot prove, and per-surface auditing decoupled from functional tests."
---

# Accessibility — Design Intent

We build for screen-reader, keyboard, and low-vision users as a first-class requirement, not a retrofit. Institutional buyers and the WL360 studies treat accessibility as a procurement gate, so **audit-ready (WCAG 2.1 AA)** is a product target.

## The one fact that shapes everything

The app renders to a single opaque `<canvas>`. Nothing reaches assistive tech until we explicitly author a name and role for it, element by element as the UI is built — accessibility is an act of authoring, not a setting switched on later. The per-widget rules live in [playwright-testing.instructions.md § Widget testability](playwright-testing.instructions.md). The omission that hides an element from a test hides it from a real screen-reader user in the same way.

## What "audit-ready" means

Three independent checks; all must hold.

- **Screen reader** — every interactive element announces what it is and does; images are described or marked decorative; reading order makes sense.
- **Keyboard alone** — every action is reachable and triggerable without a mouse; focus is always visible and never trapped.
- **Low vision** — sufficient contrast, text survives zoom/resize, nothing conveyed by color alone.

## Automated auditing proves only part

We run axe-core (WCAG 2.1 AA) against the semantics overlay. Two decisions shape coverage:

- **A11y auditing is decoupled from functional tests and covers more surfaces.** We don't script a click-through per surface. Because the URL is the workspace, an audit deep-links straight to a surface, so a surface gets accessibility coverage whether or not it has a functional spec.
- **A surface that never rendered passes vacuously.** axe over an empty or un-woken semantics tree reports zero violations — a false pass, not conformance. An audit must confirm its surface is actually present in the tree (the map must be woken first) before its result counts; an audit that cannot reach its surface fails rather than silently passing.

Beyond axe, two **deterministic** structural checks also gate the build (no pixel judgment needed): keyboard reachability + no-trap (Tab reaches several distinct controls, focus not pinned), and a non-empty page title — see [`e2e/scripts/a11y-structure.spec.ts`](../../e2e/scripts/a11y-structure.spec.ts). **Contrast cannot be gated**: screenshot sampling can't reliably separate text from non-text glyphs on the canvas, so [`a11y-contrast.spec.ts`](../../e2e/scripts/a11y-contrast.spec.ts) emits non-gating review *candidates*, not verdicts. Everything else still closes only through **manual passes**: actual screen-reader output, true focus visibility, confirmed contrast/zoom, and mobile. Treat automation as the floor, not the proof; fix an unnamed control in Dart, never allowlist a violation (permanent product debt).

## Responsibility

Accessibility is owned by whoever builds or changes the UI, in the same change — new surfaces ship with names, new flows get a manual screen-reader sanity check. Living backlog: [`e2e/web-and-accessibility-next-steps.md`](../../e2e/web-and-accessibility-next-steps.md).
