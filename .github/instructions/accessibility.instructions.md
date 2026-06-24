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

### Source-level naming gate

axe only sees the surfaces it renders. A complementary **source check** — [`scripts/a11y_floor_check.py`](../../scripts/a11y_floor_check.py), a job in [`integrate.yaml`](../workflows/integrate.yaml) — scans the whole `lib/` tree and **fails the build** if any interactive control or image is missing an accessible name or an explicit decorative marker. It covers every control in the codebase the moment it is written, not just the ~8 audited surfaces, which is how this class of gap (a button on an un-audited screen) is caught now. It proves a name is *present*, not that it is *good*: the manual passes still validate real screen-reader output. Genuine false positives (for example an image inside an ancestor `ExcludeSemantics`) take `// a11y-ignore: <reason>` on the constructor line — prefer adding the affordance.

## Naming contracts

Author these as you build.

**Enforced by the source gate** ([`a11y_floor_check.py`](../../scripts/a11y_floor_check.py)):

- **`IconButton` / `FloatingActionButton`** → `tooltip:` (its accessible name). Reuse an existing `L10n` key where one fits.
- **`Image.*`** → `semanticLabel:` if it conveys information, or `excludeFromSemantics: true` if decorative (placeholder, blurhash, background, redundant logo).

**Not gated, caught by axe or the manual passes** (apply them anyway):

- **Bare `GestureDetector` / `InkWell` acting as a button** → wrap in `Semantics(label: ..., button: true)`, or use a real button widget.
- **Decorative or redundant interactive image** → `ExcludeSemantics` / `excludeFromSemantics: true` so it isn't double-announced.

## Quick habits for anyone building UI

1. **Every control says what it does.** If it has no visible text, it needs a `tooltip:` / label. "Send message", not "tap here".
2. **Every image is described or silenced.** A `semanticLabel:` if it carries meaning, `excludeFromSemantics: true` if it's decoration. No image is left to announce its filename.
3. **Never rely on color alone.** Pair color with text, an icon, or a shape (pin state, grammar tags, error states).
4. **Mouse work must be keyboard work.** Reachable with Tab, triggerable with Enter/Space, with a visible focus ring; nothing traps focus.
5. **Visible label = accessible name.** What a sighted user reads and what a screen reader speaks should match.
6. **Group and label inputs.** Each field has a label; errors are stated in text, not just a red border.
7. **Announce what changes.** Loading, success, and error states reach assistive tech (live regions), not just a visual flash.

## Responsibility

Accessibility is owned by whoever builds or changes the UI, in the same change — new surfaces ship with names, new flows get a manual screen-reader sanity check. Living backlog: [`e2e/web-and-accessibility-next-steps.md`](../../e2e/web-and-accessibility-next-steps.md).
