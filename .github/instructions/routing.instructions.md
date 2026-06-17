---
applyTo: "lib/config/routes.dart,lib/features/navigation/**,lib/widgets/layouts/**,lib/widgets/space_navigation_column.dart,lib/widgets/navigation_rail.dart,lib/widgets/mobile_bottom_nav.dart,lib/routes/world/**"
description: "Client routing & workspace design — token lists are the single source of truth for panels over a persistent map: columns by role, a shared-width budget that opens a panel or pushes onto one, one live session."
---

# Client Routing & Workspace

The app is a **workspace of open panels over one persistent map**, and the **URL
is the single source of truth for which panels are open and in what order**. A
shared link reopens exactly what the sender saw and a refresh restores it, because
there is no second app-state store to drift from the URL. For cross-repo/external
link shapes see [deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md).

## The map is the backdrop

One map stays mounted for the whole app and never remounts, always full width
behind everything. Panels float over it as overlays, so the *visible* map is
whatever they don't cover: it grows as panels close and shrinks as they open. The
**World** control is the home of this backdrop: it clears every open panel in one
history step — so the back button restores them — to reveal the full map at world
scope. The camera biases its focal content (a location, a course region, an activity) into
the uncovered area rather than the geometric center. Because that uncovered area
shifts every time a panel opens or closes, the camera **debounces**: it settles to
the new framing in one smooth glide once the layout stops changing, rather than
re-aiming on every intermediate step and jerking. A deliberate user move (a search
result, a tapped pin) glides immediately; only the layout-driven re-framing waits
to settle.

**What the map shows is a filter, not a panel.** The map's scope rides in its own
query param, **`?m=`** — a comma-separated list of typed filter values, parsed like
the panel lists but kept separate because it is map state, not an open panel. Today
the only value is `course:<spaceid>`: it scopes the persistent map to one course
(its activities as pins) and, being just a filter, is independent of which panels
are open. A **course is, in large part, another map filter** — entering one sets
`?m=course:<id>` *and* opens the `course` panel (`?left=course`); the panel's space
id is read from the filter, never duplicated into the token. A course room is then
an ordinary `room` token over the course-filtered map (so closing the room reveals
the course, and the filter never depends on the panel set). `activeSpaceIdFor`
reads the `m` filter; leaving the course (closing its panel) clears `m` and the map
returns to world scope. New filter dimensions (region, language, activity kind)
slot into the same `m` list without touching the panel model.

## The URL is the workspace

The URL carries two ordered panel lists, a **left** list and a **right** list;
order is left-to-right placement. The **tokens are the sole source of what
renders** — nothing draws from the path. A panel's identity rides in its token (an
activity its id; a `course` panel reads its space id from the `?m=` map filter, not
the token), the map's scope rides in the separate `?m=` filter (above), and the
path itself collapses to `/`. The page builders and the chrome (rail, bottom nav)
all derive from the one token list (plus the `m` filter for the active course), so
they cannot disagree about what is open.

Paths survive only as an **inbound shape**, never a render source: external, push,
and `matrix.to` links — and the deliberately upstream `/rooms/:roomid` — are
rewritten to canonical token URLs at the router redirect *before* anything
renders, so there is exactly one representation by the time the shell builds.
Internal navigation only ever emits token URLs. This single-source rule is why a
shared link reopens exactly what the sender saw, and why closing a panel is just
dropping its token: there is no second, path-driven copy to leave standing.

## Panels are independent

Each open surface — the chat list, a live chat, a course, a settings page, the
analytics summary, a vocab or grammar detail — is its own panel with its own
close. Closing one leaves the rest open, and navigating changes which panel is
focused instead of tearing down what is already open, so a learner can close the
chat list but keep the chat, or close a course to widen the map while the chat
stays open. Section navigation keeps the right-column companions (analytics, a
detail) open; the only deliberate clear-everything is the **World/home** button,
which closes all panels at once.

Closing a panel drops its token and nothing else, because the token is the only
place it lives. The close control is an **X** on desktop (matching the right
column) and a **back arrow** on a narrow screen where the panel fills the view.
Closing the last panel reveals the bare map. A back arrow that appears *inside* a
panel is a different gesture (a push, below), not a close.

## Two columns, taken by role

A panel's side is decided by its **role**, not its content:

- **Left** — navigation and social surfaces: the chat list, a live room, a course.
  Justified to the left edge.
- **Right** — personal review and account surfaces: the analytics summary, a vocab
  or grammar detail, and the whole **profile + settings** tree. Justified to the
  right edge, so a master rests at the edge and its detail opens to the left of it.

Because role decides the side, a live chat can stay open on the left while the
learner opens analytics or settings on the right at the same time. Profile and
settings are personal account surfaces, so they belong on the right; they were
historically rendered in the left/route-driven column, which is what the migration
plan below corrects.

## One shared width

Both columns draw from a single shared width, and every panel declares **three
widths** so the allocator can place and degrade it predictably:

- **Max** — the cap it grows to; most content reads poorly much wider, so ~720 is
  the usual cap. Width no panel takes stays uncovered map.
- **Reasonable min** — the narrowest width at which the panel is still comfortable
  to use. Crossing below this is the signal to *fold* (see the ladder), not to keep
  shrinking into an unusable sliver.
- **Hard min** — the absolute floor before the panel must yield entirely.

When the open panels want more than fits, they compress from max toward their
reasonable min and the map absorbs the slack. Past that point there is exactly one
degrade move: **fold**. A column's two panels collapse into one: the **detail**
(the higher-priority panel) keeps the column, and its **master** folds behind it —
not drawn, one back-step away, revealed by closing the detail — so the pair now
costs one panel's width. Folding never discards a panel (both stay in the URL, so
widening unfolds back to two), and because the surviving panel is never torn down,
a folded live chat keeps its session.

Each column folds independently, so the widest the workspace ever needs is one
folded panel per column. The **two-column breakpoint is defined by exactly that**:
the layout stays two-column only while one folded panel per column plus the chrome
fits, and drops to single-column below it (next). Fold plus that breakpoint cover
every width — there is no peek stripe and no separate hidden state.

There is no full-screen takeover. **Width is the only canvas concept:** an empty
center is the absence of a panel; a bounded panel is the default; a full-bleed
surface is a panel that raises its max to the viewport; and a surface that must
hold the screen alone marks itself **exclusive**, collapsing the others while it is
open (an in-progress activity is the main example).

**Single-column mode is the floor**, not a separate layout: below the two-column
breakpoint (narrow screens; phones always) the chrome swaps — the side rail becomes
bottom navigation, the left inset goes to zero — and only the focused panel shows.
The others stay in the URL, reopened from the persistent chrome (the rail or bottom
nav for a section, the cluster for analytics), so nothing is lost, just not drawn at
once. Every master/detail flow is already folded here: one panel, navigated with a
back arrow.

## Opening, pushing, and folding

One vocabulary covers how content opens (the noun stays **panel**, matching the
code's `Panel*` types; it is the industry "pane"):

- **Open a panel** — add a coexisting panel. Each column holds **up to two panels**
  (a master and its detail), left and right independently, so the workspace shows up
  to four when width allows. Two panels in a column are a master/detail split.
- **Push / pop** — open a page *within* a panel, onto that panel's **stack**; the
  back arrow **pops** it. Each panel is its own little navigator. Security → change
  password, a chat → its members, a settings menu → a page beyond the budget: all
  pushes.
- **Fold / unfold** — the width-driven version of a push: when the budget can no
  longer honor reasonable-min widths, a column's **lower-priority** panel (the
  master) **folds** behind its detail — not drawn, one back-step away — and
  **unfolds** back to two panels when width returns. A fold is a push the layout
  performs instead of the user.

**Opening is a fit test, not a depth count.** A surface opens a new panel when the
column is under its two-panel budget *and* the budget can grant the newcomer its
min width; otherwise the page **pushes** onto the panel it came from (back arrow).
Going deeper than a detail always pushes. Mobile has a one-panel budget, so every
open is a push — the fully-folded end of the same rule. A user push is a forward
history step and a pop is a step back; a width-driven fold/unfold *replaces* the
current entry, because an automatic relayout is not something the user should have
to "undo".

## How each surface opens

One entry point is canonical per surface, on every form factor, so the same tap
behaves the same on mobile and desktop.

| Surface | Opens from | Column | As |
|---|---|---|---|
| World map (home) | app root, World rail | the backdrop | always mounted; the World button clears every panel |
| Course | a space in the rail, a map pin | left + `?m=` filter | sets `?m=course:<id>` (map scope) **and** opens the `course` panel (master); tabs ride in the token param |
| Chat list | the rail | left | open panel (master) |
| Live chat / session | a chat-list row, an activity launch, **a course room row** | left | open panel (detail); one live at a time. A course room rides over the course filter (`?m=course:<id>` stays) so closing it reveals the course |
| Chat members / settings | the chat header | the chat panel | push |
| Analytics (vocab / grammar / sessions) | a top-right cluster tracker | right | open panel (master) |
| Level | the avatar's level badge | right | open panel (an analytics tab) |
| A construct detail | tapping a vocab/grammar item | right | open panel (detail), left of its summary; **one at a time** — a new detail replaces the open one (the right-column mirror of one-live-session); folds in under pressure |
| Profile + settings menu | the top-right cluster avatar | right | open panel (master) |
| A settings page (learning, style, security, …) | a settings-menu row | right | open panel (detail), or pushed onto the menu when folded |
| A settings leaf (password, blocked users, emotes, …) | within its settings page | the settings panel | push |
| Add-course wizard (start-my-own / browse / enter-code) | the rail "+" → hub | left | open panel (a step is the token param); deeper steps stay route-driven |
| An in-progress activity | a course / the map | full-bleed | exclusive |

## One live session at a time

At most one **live** chat or activity session is open at once. The Matrix room
timeline is shared rather than reference-counted, so two live views of a room
overwrite each other. A completed activity session opens as its **actual chat**,
locked from new messages — the real timeline, with the wrap-up summary posted in
it as a message, not a separate summary card — so it is a live view too and obeys
the same rule: opening a new session replaces the current one. *(Future: give a
room its own session state by folding the choreographer controller into the chat
controller, which would lift this limit and could let a completed session open as
a coexisting read-only review.)*

## The map never rebuilds

The map is one widget, mounted once for the session and preserved across every
navigation by a single stable key, so its tiles, camera, and pins survive while
panels come and go. **Navigating must never rebuild it** — only change what it
*shows*: its scope (world vs. a course region), its focus (a located activity), and
the camera padding that keeps focal content in the uncovered area. Because those
inputs ride in tokens, and inbound paths are rewritten to tokens before the shell
builds, the map reads one consistent source each frame and can glide its content
instead of flipping or reloading. Two things protect this and must hold:

- **Stay inside the shell.** The map only persists while the workspace shell stays
  mounted; routing through a non-shell top-level page (login, onboarding, logs)
  tears it down and is the one true remount. Auth and error flows are the only
  legitimate exits.
- **Resolve scope and focus once, then update idempotently.** A scope or focus read
  from two places, or resolved asynchronously in two steps, makes the map flip
  world↔course or glide twice. Carry enough identity in the token to resolve scope
  without a round-trip, publish content changes after the frame, and no-op an
  unchanged value so an identical re-publish never re-fits the camera. (The
  layout-driven re-framing is debounced so this stays smooth — see *The map is the
  backdrop*.)
- **Floating chrome sizes to its content, never the Stack.** The shell `Stack` is
  `StackFit.expand`, which forces a *non-positioned* child to full size. A chrome
  widget with an opaque root (the nav rail's `Material`, a card's surface) would
  then paint over the whole map below it — the map lays out full-size but is hidden
  (a real bug: the rail covered the map on web; mobile was fine only because the
  rail is `SizedBox.shrink` there). Wrap any floating chrome (rail, overlays) in an
  `Align`/`Positioned` so it sizes to its content and the map stays full-bleed
  behind it.

## The cluster is the right column's entry point

A persistent cluster pinned to the top-right of the map opens the right column: the
user's avatar ringed by experience progress and level, their target-language flag,
and trackers for completed sessions, grammar, and vocabulary. Tapping a tracker
opens that metric as a right-column panel, and its detail blooms to the left;
tapping the **avatar** opens the profile + settings master, and the **level badge**
on the avatar opens the Level analytics tab (level is analytics, reached from the
badge rather than a tracker — a temporary placement until the badge becomes its own
element). The
cluster stays pinned above the panels, because it is the anchor the right column
justifies against.

## History follows the workspace

The URL holds the workspace, so the back button, shared links, and reload all move
through the same state: opening a panel or pushing within one is a forward step and
closing a panel or popping is a step back, while refocusing, reordering, and an
automatic fold/unfold *replace* the current entry rather than adding history.

## Adding a panel

A new surface is a registry entry, not a new route tree: declare its column (which
fixes its role and justification), its three widths (max, reasonable min, hard
min), its collapse priority, whether it is exclusive, and whether it opens its
detail as a panel or pushes it. The parser, the width allocator, and the chrome
pick it up from there. A settings or profile page is just a right-column entry
whose deeper levels are reached by a push.

## Migration plan (temporary — remove when complete)

> Transitional only. Delete this section once the token-only model and the
> settings/profile move have landed; the sections above are the durable design.
> This records the order that keeps the app shippable between steps.

Today two systems coexist: the token lists *and* a legacy route-driven card
(`_MainView`) that renders a section from the path when no token names it. That
dual source is why closing a section has to bounce to `/` (drop the token *and*
leave the path), and why settings pages — rendered as a route-driven center detail
with no width floor — get crushed to an overflowing sliver (the live overflow bug).
The plan retires the path as a render source and moves settings/profile to the
right column.

1. **Width primitives (additive, low risk).** [done] The reasonable-min width is on
   every registry entry and is the allocator's fold trigger. The per-panel push/pop
   stack is the panel's own back arrow rewriting its token's param (settings menu↔page,
   analytics summary↔detail) — a full in-panel Navigator was not needed.
2. **Tokens are the sole source — `_MainView` is deleted. [done]** Chats, a course,
   analytics (incl. level), profile/settings, and the add-course wizard's first step
   (`addcourse:own`/`browse`/`private`) are all token-driven, with inbound redirects
   rewriting their legacy paths at the router (and `/rooms/:roomid` kept as an inbound
   shape). The route-driven `_MainView` left card is gone; closing a section drops its
   token. The wizard's first step is a left-column **panel host** (the proven
   card pattern) — not a full-bleed canvas, which rendered blank. Its deeper steps
   (`/courses/own/:courseid` …) stay route-driven detail.
3. **Settings and profile move right.** [done] Profile + every settings page is a
   right-column panel in the shared card chrome (close X, or a back arrow on a pushed
   leaf); menu rows open the page as a push; the dead `/rooms/settings/...` links and
   the security leaves are token-driven; the learning-settings unsaved-changes guard
   is preserved. This fixed the overflow bug.
4. **Fold under width pressure.** [done] The allocator folds the lowest-priority
   panel out of the layout (marked `hidden`, not drawn, no stripe) until the rest fit
   at their reasonable-min, so a column's master/detail pair collapses to one panel —
   the detail (higher priority) keeps the column and its session, the master one
   back-step away (closing the detail reveals it). Both tokens stay in the URL, so
   widening unfolds back to two panels. The width-based `isColumnMode` threshold drives
   the single-column floor (rail → bottom nav, left inset → 0, focused panel only).
   This replaced the peek stripe; `PanelVis` is now just `full` / `hidden`.
5. **Course off the path → `?m=` map filter.** [done] A joined course is the
   `?m=course:<id>` map filter (read by `activeSpaceIdFor`) plus a `course` panel,
   not a `/courses/:spaceid` route. Inbound redirects rewrite the legacy bare course
   path (preserving any `?activity=`/query) and the course-room path
   (`/courses/:spaceid/:roomid` → `&left=course,room:<roomid>`) to the workspace
   form; `goToSpaceRoute` opens an in-course room as a `room` token over the filter.
   [to do] The deeper course-management paths (`details/edit`, `invite`, `analytics`,
   `addcourse/:courseId`, and room sub-routes like `/search`) stay route-driven for
   now — their 3rd path segment is a literal, not a `!room`, so the room redirect
   skips them; converting them to in-panel pushes is a later step.

Each step ships independently and leaves the app green.
