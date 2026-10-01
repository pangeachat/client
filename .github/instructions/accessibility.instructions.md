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

## Text scaling

**The device's text-size setting is the only text-size control.** The app ships no
font-size setting of its own — a per-app slider duplicates a control the user has
already set at the OS level.

Two Flutter defaults work against this, and both are invisible at 1.0× — a surface can
look correct in every screenshot and still ignore the setting entirely:

- **`RichText` defaults to `TextScaler.noScaling`.** It reads no `MediaQuery`. Any
  `RichText` must be passed `textScaler: MediaQuery.textScalerOf(context)`. Plain
  `Text` and `Text.rich` resolve the scaler themselves and need nothing.
- **`TextPainter` defaults to `TextScaler.noScaling` too.** Where text is measured and
  rendered separately — the token underlines and highlight boxes — the painter and the
  widget must be given the *same* scaler, or the decoration lands off its word. A width
  cache keyed on text and font size alone is stale the moment the scale changes; the
  scale belongs in the key.

**Decoration is the exemption.** Non-text glyphs that are not read — XP particles,
emoji bursts — stay at a fixed size, because they travel along trajectories measured in
pixels and a scaled glyph drifts off its own path. Mark them `TextScaler.noScaling`
explicitly and say why; an unmarked fixed size is indistinguishable from an oversight.

**Fixed-size boxes around text must grow with the text inside them.** A glyph in a hard-coded `SizedBox` is clipped at 2×: let the box size itself, or scale it by the factor the device scaler applies at the font size of the text it holds (`TextScaler.factorAt`). Scaling it by its own dimension is wrong — `TextScaler.scale` takes a font size, and Android 14+ answers from a curve where small text grows more than large, so a 250px word card is answered as if it were 250pt type: it grows by the factor huge text gets rather than the factor its 16pt contents get, and still clips. Anything that takes a plain scale multiplier needs the same factor.

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

- **`IconButton` / `FloatingActionButton`** → `tooltip:` (its accessible name). Reuse an existing `L10n` key where one fits. Exception: a `FloatingActionButton.extended` already has a visible `label:` that is its name, so do **not** add a tooltip there — it double-reads. (The floor-check accepts `tooltip:` *or* `label:`.)
- **`Image.*`** → `semanticLabel:` if it conveys information, or `excludeFromSemantics: true` if decorative (placeholder, blurhash, background, redundant logo).

**Not gated, caught by axe or the manual passes** (apply them anyway):

- **Bare `GestureDetector` / `InkWell` acting as a button** → wrap in `Semantics(label: ..., button: true)`, or use a real button widget.
- **Decorative or redundant interactive image** → `ExcludeSemantics` / `excludeFromSemantics: true` so it isn't double-announced.

## Focus after an in-place content swap

Some pages replace their content under chrome that stays put: the onboarding wizard swaps its step under a persistent header. On the web the control that was just pressed disappears with the old content, and with nothing claiming focus the screen reader is left on the page root or on the Back button, unable to reach the new content (#7582).

**After an in-place swap, focus lands on the whole step — the group holding the header, the center content and the forward button — and the screen reader announces the step by its page name.** The page clears its focus history at the swap so no older control is restored, and the group claims focus as one discrete event once the swap has settled. It is not a Tab stop: keyboard users still move straight to the controls inside.

**Inside the step the header is flat and the center content is one named group.** The Back button and the progress bar, announced as "Step n of m", are direct children of the step, never wrapped in a group of their own, so one step up from the center content lands beside them with no further group to enter. The Back button is rebuilt with each step, so the control a screen reader pressed leaves the tree like any other pressed control; a cursor left on it would otherwise keep a stale view of the step around it. The center content — the title and the choices — is a group named by the step's visible title, which is not read a second time as a child; on a step that scrolls, that group is the scroll region itself, so scrolling adds no level of its own. Shared implementation: [`OnboardingPageGroup`](../../lib/routes/onboarding/onboarding_page_group.dart), [`OnboardingHeader`](../../lib/routes/onboarding/onboarding_header.dart), [`OnboardingStepBody`](../../lib/routes/onboarding/onboarding_step_views/onboarding_step_body.dart).

## One Tab stop per list

A list of like controls — the nav rail's joined courses, the chat list's rooms, the world map's drawn pins — is one Tab stop, not one per item: a keyboard user reaches whatever sits past the list in one press, the way a screen-reader user steps over a group. The rail's three section icons (World, Chats, Courses) stay stops of their own, so Tab walks the rail the way a screen reader browses it: the three items, then the joined-course list as one group. Inside the list, Up and Down move focus one item at a time and stop at the ends (no wrap, because losing your place in a long list disorients); Enter or Space activates the focused item; Tab or Shift+Tab leaves. Tab lands on the item last focused in the list, else the selected item (the open chat, the lit rail section), else the first item on screen — never on nothing, even when the selected item is scrolled out of view. Shared implementation for widget lists: [`RovingFocusGroup`](../../lib/pangea/common/widgets/roving_focus_group.dart), which an item joins by its `rovingId`; the map pins draw to a canvas and author the same behaviour themselves ([world-map.instructions.md](world-map.instructions.md)). The course page's Chats section does not use it yet.

## Long-press menus

A long-press menu can be opened without a long press. On iOS and Android, the screen reader gets the menu from the node's long-press action and from a named custom action. Flutter's web engine sends neither to the browser, so on web a widget opts in: its semantics node carries the [`ShowMenuLongPress`](../../lib/pangea/common/utils/show_menu_long_press.dart) identifier, and the browser's `contextmenu` event on that node, which VoiceOver's "show menu" sends, opens the long-press menu instead of the browser's page menu. Chat-list rows opt in; other long-press menus do not yet. While the semantics tree is on, a mouse right-click on an opted-in node opens the same menu.

## Focus rings

Every custom control authors its own keyboard focus ring. The ring shows only while the learner moves by keyboard, never on touch or a pointer click, and it must clear 3:1 against everything next to it (WCAG 2.1 1.4.11). Its colour and shape follow from what it sits on. Shared implementation: [`FocusRingTapTarget`](../../lib/pangea/common/widgets/focus_ring_tap_target.dart).

- **On app chrome the ring is gold** (`goldGraphic`, see [design-tokens.instructions.md](design-tokens.instructions.md)). This covers the map's zoom controls, the cluster's avatar, stat trackers and language flag, and the nav rail's course avatars.
- **Where a ring crosses map tiles or the XP ring, it is two-tone:** a white band toward the control and a near-black band toward its surroundings. No single colour clears 3:1 over arbitrary tiles, but one of these two always does. This covers the map pins ([world-map.instructions.md](world-map.instructions.md#keyboard-access)), the level medal and the narrow bar's level badge. Next to the XP ring and the shield, the gold ring measured 1.0 to 2.9:1 (#9114).
- **On a solid mark the ring follows the mark's outline** (the level shield, the hexagon badge) instead of circling it, because a circle around the shield read as a stray artifact (#8067). The hexagon badge's ring sits inside its own box, because the narrow bar's loading shimmer masks only that box and anything painted outside it stays in colour (#7801).

## Quick habits for anyone building UI

1. **Every control says what it does.** If it has no visible text, it needs a `tooltip:` / label. "Send message", not "tap here".
2. **Every image is described or silenced.** A `semanticLabel:` if it carries meaning, `excludeFromSemantics: true` if it's decoration. No image is left to announce its filename.
3. **Never rely on color alone.** Pair color with text, an icon, or a shape (pin state, grammar tags, error states).
4. **Mouse work must be keyboard work.** Reachable with Tab, triggerable with Enter/Space, with a visible focus ring; nothing traps focus. A list of like controls is one Tab stop with the arrow keys moving inside it — see [One Tab stop per list](#one-tab-stop-per-list). A long-press menu also opens without a long press — see [Long-press menus](#long-press-menus).
5. **Visible label = accessible name.** What a sighted user reads and what a screen reader speaks should match.
6. **Group and label inputs.** Each field has a label; errors are stated in text, not just a red border.
7. **Announce what changes.** Loading, success, and error states reach assistive tech (live regions), not just a visual flash.

## Responsibility

Accessibility is owned by whoever builds or changes the UI, in the same change — new surfaces ship with names, new flows get a manual screen-reader sanity check. Living backlog: [`e2e/web-and-accessibility-next-steps.md`](../../e2e/web-and-accessibility-next-steps.md).
