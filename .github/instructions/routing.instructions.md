---
applyTo: "lib/config/routes.dart,lib/features/navigation/**,lib/widgets/layouts/**,lib/widgets/space_navigation_column.dart,lib/widgets/navigation_rail.dart,lib/widgets/mobile_bottom_nav.dart,lib/routes/world/**"
description: "Client routing & workspace design — the URL (course context + panel-token lists) is the single source of truth for panels over a persistent map: columns by role, a shared width budget that opens or folds panels, one live session."
---

# Client Routing & Workspace

The app is a **workspace of open panels over one persistent map**, and the **URL
is the single source of truth for what is on screen**: which panels are open, in
what order, and which course the workspace is scoped to. A shared link reopens
exactly what the sender saw and a refresh restores it, because there is no second
app-state store to drift from the URL. Link shapes arriving from outside the
client (push notifications, emails, the bot) are the org-level contract in
[deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md).

## Design goals

1. **Maximize use of available space.** Open a child detail in a new panel when
   there is room; fold it onto its parent when there is not; close siblings to
   make room for new siblings.
2. **Keep the URL short and legible.** Anyone on the team should be able to read
   a workspace URL and say what is on screen.
3. **Survive refresh and sharing.** Navigation state lives in the URL and
   nowhere else.
4. **No special exceptions.** One unified logic; a new surface is a registry
   entry, not a new rule.
5. **Everything a panel needs rides in its token.** Loose query params exist
   only on inbound links; the redirect folds them into tokens before anything
   renders.
6. **One writer.** Internal navigation goes through the `WorkspaceNav` helpers;
   `LegacyRedirects` is the only place inbound legacy shapes are rewritten.

## Reading a workspace URL

The whole grammar in one place. The path is always `/`; state rides in the query:

- **`?c=<spaceid>`** — the **course context**: the course the workspace is scoped
  to, absent for the whole world. Read by the map and the course panels alike
  (see [The course context](#the-course-context)).
- **`?left=` and `?right=`** — comma-separated ordered lists of **panel tokens**,
  one token per open panel, ordered from bottom to top.
- A token is **`type:param`**. The type names the surface (`chats`, `room`,
  `course`, `settings`, `analytics`, `vocab`, `activity`, …); the param carries any subpages within the given surface, and extra information needed to render the page. Pushed subpages within the param after separated with forward slashes. Extra information (info that would typically be in query parameters) after added to the end of the param, and separated by periods.

| URL | What is on screen |
| --- | --- |
| `/` | the bare world map |
| `/?left=chats,room:!abc` | the chat list, with chat `!abc` open beside it |
| `/?c=!s&left=course&right=analytics:vocab` | inside course `!s`: the map scoped to the course, the course card on the left, vocabulary analytics on the right |
| `/?right=settings,settingspage:security/3pid` | the settings menu, with the Security page open beside it, pushed to its change-email leaf |
| `/?c=!s&left=course:more,coursepage:invite` | the course card on its More tab, with the invite page open beside it |
| `/?right=analytics:vocab,vocab:abrigadoro.adj` | vocabulary analytics, with the word detail for "abrigadoro" (adjective) open beside it |

The rules that keep the grammar legible:

- **First beneath, second on top — in both lists.** A column's first token is
  the panel that folds behind under width pressure; the second stays visible.
  For a master/detail pair that means master first, then detail; for a pair the
  registry does not relate (a course card with a live room beside it) it means
  context first, then content. Each column draws its first panel at its own
  screen edge with the second blooming toward the center — but that
  justification is the renderer's concern; the URL never mirrors pixel
  placement.
- **Token params are short, human-readable values.** Never JSON or any nested
  structure, and never a repeat of what the token type already says: a construct
  detail is `vocab:abrigadoro.adj` — the construct type is the token type, so it
  does not appear again inside the param.
- **Params carry open-ended, all-language content safely.** A lemma can be any
  text in any script — multiword, with punctuation. Every param value must
  round-trip the URL losslessly, and content can never collide with the
  grammar's structural separators (the comma between tokens, the colon after
  the type, the slash of a push, and any field separator inside a param):
  content is encoded so a comma inside a lemma cannot split the list. This contract is pinned by unit tests over hostile
  values — multiword lemmas, non-Latin scripts, and the separator characters
  themselves.
- **One vocabulary across the grammar.** The same surface always has the same
  name in every token: analytics tabs and practice modes share `vocab` /
  `grammar` (the legacy `morph` spelling survives as an accepted inbound form
  only).
- **Ids appear exactly once.** The map and the course panels share the one space
  id in `?c=`; an activity's id (and, when resuming, its bound session room) ride
  in the activity token's own param.

**Compatibility.** The parser normalizes a registry master/detail pair to
master-first whatever order a link carries (the
[panel registry](../../lib/features/navigation/panel_registry.dart) knows which
type is whose master) and keeps the given order for pairs the registry does not
relate. That is the whole compatibility story: **the client is the only
producer of its URLs, so retired shapes and spellings are simply deleted, not
redirected** — old bookmarks and stale tabs from earlier releases are not
maintained (a deliberate call at current scale, #7467). The inbound URL
contracts are the shareable standalone activity link (`/<uuid>`) and the course
join link (`/join_with_link?classcode=<code>`, the CloudFront short-code 302
target, plus its native `/join` spelling — #7524), which
[`LegacyRedirects`](../../lib/features/navigation/legacy_redirects.dart) folds
into their `activity` / `addcourse:private/<code>` tokens before render.

## The core model

### The URL is the workspace

The context param and token lists are the sole source of what renders — nothing
draws from the path, which always collapses to `/`. The page builders and the
chrome (rail, bottom nav, cluster) all derive from the same tokens, so they
cannot disagree about what is open. Closing a panel is just dropping its token:
there is no second, path-driven copy to leave standing.

External pointers never carry workspace paths either: a push notification
resolves through its structured content keys and a `matrix.to` link through the
in-app link handler — both emit token URLs in code
([deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md)).
The URLs that arrive from outside — the shareable standalone activity link
(`/<uuid>`) and the course join link (`/join_with_link?classcode=<code>`) — are
rewritten to their tokens at the router redirect before anything renders — so
there is exactly one representation by the time the shell builds.

### The course context

`?c=<spaceid>` is the workspace's **course context** — a scope, not a panel. One
value does two jobs, which is exactly what keeps them from ever disagreeing:

- It **scopes the map** to that course: the course's activities as pins, instead
  of the whole world.
- It **identifies the course-family panels**: the `course` card, its
  `coursepage` details, and an activity opened within the course all read the
  space id from it.

Entering a course — from the rail, a map pin, or a Courses-list tile — sets
`?c=` and opens the `course` panel. A course room is then an ordinary `room`
token over the course-scoped map.

**Context persists, and navigation never consumes it.** Opening, closing, and
switching panels — closing the course card itself, tapping an activity pin,
moving to Chats or Settings — all leave `?c=` untouched; closing panels is
precisely how you get a clear look at the scoped map (#7087). The context
changes in three ways: selecting another **course** replaces it; the
**World/home** control clears it; and **leaving or deleting the course you are
in** clears it. The latter two are the same deliberate full reset — dropping
every open panel *and* the context together in one history step (so the back
button restores both) and revealing the world map at its personal default.
Leaving or deleting a *course* is the only membership change that resets scope:
leaving or deleting a chat, DM, or activity just drops that one panel and leaves
the rest of the workspace — notably the list it sat in — standing (#7561).
Surfaces that carry no context of their own (the Courses hub, Chats, Settings)
overlay the map you left without changing it.

Pure **map filters** (region, language, activity kind) are a future, separate
`?m=` list — display refinement, not workspace context. Nothing uses it today.

### Navigate by token

Internal navigation MUST go through the
[`WorkspaceNav`](../../lib/features/navigation/workspace_nav.dart) token helpers
(or the token-producing `PRoutes` builders) — `setSection`, `openSettings`,
`openCoursePage[For]`, `openConstructDetail`, `closeLeft`, and friends. Two
smells, both forbidden in feature code:

- **A path literal in a `.go(...)`** (`/chats`, `/rooms/<id>`,
  `/courses/<id>/...`). The retired section, room, and course paths have no
  redirects behind them anymore — an internal path navigation is simply a dead
  link (the redirect-bounce era is how the dead-`/chats` bug #7067 happened).
  This includes the standalone activity link `/<uuid>`: it is the shareable
  artifact for the outside world, so in-app code opens activities through the
  token helpers, never by emitting the path.
- **Hand-editing the query string.** Panels never assemble or sweep query params
  themselves; the query-editing utilities are internal to the navigation layer.
  If a surface needs a navigation the helpers can't express, add a helper — that
  keeps the grammar in one place.

**Everything a panel needs rides in its token's fields — there are no loose
params.** The one external URL producer, the shareable `/<uuid>` activity link,
may carry `launch=`/`roomid=`/`autoplay=`; its single redirect arm folds them
into the `activity` token's fields before anything renders. Internal navigation
never emits or strips a loose param: a panel reads everything it needs from its
token, the same place a tab or a pushed page rides. There is no second channel
to sweep; a param-sweeping call in feature code means some state is missing its
token home.

A behavioral flag in a token param then follows the ordinary navigation rules:

- `autoplay` re-fires on refresh exactly as it does anywhere on the web: the
  URL describes how the panel opens, and a shared link opens the same way for
  its recipient.
- The automatic transition a `launch` flag triggers (straight into the session)
  *replaces* the history entry — the same rule as a width-driven fold — so the
  back button never replays the launch.
- Internal navigation builds tokens from state through the helpers, so a flag
  naturally drops on the next in-panel navigation rather than lingering.

This includes the room params inherited from the FluffyChat base (`event=`
jump-to-message, `body=` share-text, `filter=`): they are inbound shapes like
any other and fold into the `room` token's param. There are no exceptions — the
client is a hard fork, and grammar consistency outranks staying close to the
FluffyChat base (see
[codebase-organization.instructions.md](codebase-organization.instructions.md)).

### The map is the backdrop

One map stays mounted for the whole app, always full width behind everything.
Panels float over it as overlays, so the visible map is whatever they don't
cover: it grows as panels close and shrinks as they open. The camera biases its
focal content (a location, a course region, an activity pin) into the uncovered
area rather than the geometric center. Because that uncovered area shifts
whenever a panel opens or closes, the layout-driven re-framing **debounces** —
one smooth glide once the layout settles, instead of re-aiming on every
intermediate step. A deliberate user move (a search result, a tapped pin) glides
immediately.

### The map never rebuilds

The map is mounted once per session and preserved across every navigation, so
its tiles, camera, and pins survive while panels come and go. Navigating must
never rebuild it — only change what it *shows*: its scope (world or a course),
its focus (a located activity), and the camera padding. Three rules protect
this:

- **Stay inside the shell.** The map persists only while the workspace shell
  stays mounted; routing through a non-shell top-level page (login, onboarding,
  logs) tears it down. Auth and error flows are the only legitimate exits.
- **Resolve scope and focus once, then update idempotently.** A scope read from
  two places, or resolved in two asynchronous steps, makes the map flip between
  world and course or glide twice. The URL carries enough identity to resolve
  scope in one read, and re-publishing an unchanged value never re-fits the
  camera.
- **Floating chrome sizes to its own content.** The map is the base layer
  everything overlays; an overlay that stretches to the full shell paints over
  the entire map and hides it (a real bug we hit on web). Keep each overlay
  bounded to what it actually draws.

## The panel model

### Two columns, taken by role

A panel's side is decided by its **role**, not its content:

- **Left** — navigation and social surfaces: the chat list, a live room, a
  course. Justified to the left edge.
- **Right** — personal review and account surfaces: analytics, a vocab or
  grammar detail, and the whole profile + settings tree. Justified to the right
  edge.

Because role decides the side, a live chat can stay open on the left while the
learner opens analytics or settings on the right at the same time.

### Panels are independent

Each open surface is its own panel with its own close, and closing one leaves
the rest open (close the chat list but keep the chat; close a course card to
widen the map while the chat stays open). Selecting a section from the **left
nav rail** (Chats, Courses, a course) **replaces** the open left-column panels
with that section rather than stacking beside them, while right-column
companions (analytics, a detail) stay open. Opening a course from a map pin or a
Courses-list tile is navigating within your content, not a rail section switch,
so it keeps an open chat and swaps only the course. The one clear-everything is
the **World/home** control (see [The course context](#the-course-context)).

Closing the last panel reveals the map at its current scope — the course's map
if a context is set, the world otherwise.

### Closing a panel: X or back arrow

Every panel shows exactly one of two close affordances, derived from the
navigation tree and the surviving context — never from remembering where the
user came from:

- A **back arrow** means there is somewhere to go back to. It pops a page pushed
  within the panel, unfolds a folded master, or — for a panel whose contextual
  parent is present — returns to that parent: an activity plan under a course
  context closes back to the course card.
- An **X** means closing simply reveals what is beneath: the other panels and
  the map.

**Navigation never clears context or any other state to force one affordance or
the other.** If a panel shows the wrong affordance, its tree placement or the
context handling is wrong — fix that, not the button.

**Every panel shows exactly one header, and the shared chrome is the default.**
A panel is wrapped in the shared header (the close/back control plus its title)
unless it explicitly opts out and renders its own — which a page may do when it
needs chrome the shared header can't express: a leaf-specific title the token
doesn't carry, or a trailing action. An opting-out page takes the panel's close
control and places it in its own header, so the affordance rule above still
holds. Two failure modes this rule exists to prevent, one on each side:
**no header** (a page that renders none while the wrapper was dropped — the
learner has no title and no way out, #7763) and **two headers** (a page that
draws its own *and* gets wrapped). Because "renders its own chrome" is invisible
to the wrapper, the opt-out is declared per page (settings:
`SettingsPageEnum.addHeader`) and pinned by tests — a new page that forgets to
declare gets the default, which is the safe direction.

### The navigation tree: parent, child, sibling

Every surface declares where it sits in one explicit tree, in the
[panel registry](../../lib/features/navigation/panel_registry.dart) — the
authoritative per-panel mapping of each type's parent and the slots its siblings
share. The parser, the fold, and the single-column focus all read that one
structure, so there is no separate priority or recency system to drift from it:

- A **child** declares its **parent** (the master it details). A child opens
  beside its parent when width allows and otherwise **stacks** on it (the parent
  folds behind the child). A `room` is the `chats` list's child; a settings page
  is the settings menu's child; a vocab/grammar detail is the analytics
  summary's child. A parent with no parent of its own is a **root** (a section
  master).
- **Siblings** are children that share one slot: they can't coexist, so opening
  one replaces the others. Vocab and grammar are siblings (one construct detail
  at a time); a live `room` and a `session` review are siblings (one live view).
  This is why grammar replaces vocab rather than stacking on it.

Most trees are two generations (the chat list, then a chat; analytics, then a
construct detail). A deeper level — security, then change-password — is a
**push within** the child's own panel (riding its token param), not a third
panel, so the panel-level tree stays parent and child. **Priority is only a
tiebreak** between independent trees (which master folds first when several
pairs are under pressure; which leaf is focused when independent panels are
open). A child never folds and always wins focus over its own parent, regardless
of priority.

### Opening, pushing, and folding

One vocabulary covers how content opens:

- **Open a panel** — add a coexisting panel. Each column holds **up to two
  panels** (a master and its detail), left and right independently, so the
  workspace shows up to four when width allows.
- **Push / pop** — open a page *within* a panel, onto that panel's own stack;
  the back arrow **pops** it. Each panel is its own little navigator. Security
  then change-password, a chat then its members: all pushes.
- **Fold / unfold** — the width-driven version of a push: when the width budget
  can no longer honor reasonable minimums, a column's **master folds** behind
  its **detail** — not drawn, one back-step away — and **unfolds** back to two
  panels when width returns. When a column's two panels are not a registry
  master/detail pair (a `course` card with a live `room` beside it), the same
  rule applies positionally — the first token folds behind the second — so a
  chat opened in a course folds the course card behind it, and closing the chat
  reveals the card as it was left (#7332).

**Panel widths come in three named families, not per-panel numbers (#7572).**
Panels that can replace each other in a slot share one min/comfort/ideal
triple (`PanelWidths` in the registry), so navigating between them never
resizes the column — the width-jump QA kept catching. The families: **list**
(the thin index columns — the chat list, the DM-create picker), **wide** (the
live/content surfaces — a chat, a session, an activity or course card, and the
course flow pages, which host forms and media and earn the same room), and
**tool** (the entire right column — settings, analytics and its details,
practice — one width for every tool panel). The only remaining width step is
the deliberate list↔wide difference. A new panel type joins a family; it does
not invent its own widths.

**Opening is a fit test, not a depth count.** A surface opens a new panel when
the column is under its two-panel budget *and* the budget can grant the newcomer
its minimum width; otherwise the page **pushes** onto the panel it came from.
**When there is room, a detail opens beside its master — folding is only ever a
response to width pressure, never a default** (the one deliberate exception is
practice, below). Going deeper than a detail always pushes. Mobile has a
one-panel budget, so every open is a push — the fully-folded end of the same
rule.

This is the rule for **every page that opens off a master**, and the two trees
that have one work identically: a **settings page** off the settings menu and a
**course management page** (invite, edit, access, change-course) off the course
card both open as a coexisting detail beside their master when width allows, and
fold only under pressure. A detail never *replaces* its master outright — the
master stays one step away (beside it, or folded behind it), so closing the
detail reveals the menu or card it came from. (A regular chat's own
members/search are the exception: they push *within* the chat, because they
belong to that one timeline, not beside it.)

## Sizing and form factor

### One shared width

Both columns draw from a single shared width, and every panel declares **three
widths** so the allocator can place and degrade it predictably:

- **Max** — the cap it grows to; most content reads poorly much wider, so ~720
  is the usual cap. Width no panel takes stays uncovered map.
- **Reasonable min** — the narrowest width at which the panel is still
  comfortable to use. Crossing below this is the signal to *fold*, not to keep
  shrinking into an unusable sliver.
- **Hard min** — the absolute floor before the panel must yield entirely.

When the open panels want more than fits, they compress from max toward
reasonable min and the map absorbs the slack. Past that point the one degrade
move is **fold** (defined in the panel model above), which drops the pair's cost
to one panel's width. Folding never discards a panel — both stay in the URL, so
widening unfolds back to two — and the surviving panel is never torn down, so a
folded live chat keeps its session.

Each column folds independently, so the widest the workspace ever needs is one
folded panel per column; the **two-column breakpoint** is defined by exactly
that, and the layout drops to single-column below it. A user push is a forward
history step and a pop is a step back; a width-driven fold or unfold *replaces*
the current history entry, because an automatic relayout is not something the
user should have to undo.

There is no full-screen takeover. **Width is the only canvas concept:** a
full-bleed surface is just a panel whose max is the viewport, and a surface that
must hold the screen alone could mark itself **exclusive**, collapsing the
others — though no surface needs that today.

### Single-column (narrow and mobile) mode

**Single-column mode is the floor**, not a separate layout: below the two-column
breakpoint (narrow windows; phones always) the chrome swaps — see the mobile
chrome below — and only one panel shows: the
**most-recently-opened** one, so opening a panel always brings it forward.
Recency is ephemeral view state, not part of the shareable URL; on a cold link
or a refresh the shown panel falls back to the active **leaf** of the tree (a
child over its parent, ties broken by priority). Recency matters because
priority alone would let a live chat silently out-rank a freshly opened settings
or analytics panel. The other panels stay in the URL, reopened from the chrome,
so nothing is lost — just not drawn at once. Every master/detail flow is already
folded here: one panel, navigated with a back arrow.

**The mobile chrome is substantially different from web.** The side rail becomes
a **floating bottom nav widget** (the expandable rounded container in
[Single-column bottom nav](#single-column-bottom-nav) below), and the cluster
becomes a **horizontal analytics bar** pinned to the top of the safe area
([Single-column analytics nav bar](#single-column-analytics-nav-bar)). A **search bar**
floats above the nav widget with map filters above it
([Single-column search bar](#single-column-search-bar)). Analytics and Profile
are reached from the top bar, not the bottom nav. Further-nested surfaces — a
live chat, including a launched activity session — open **full-screen**,
covering the bottom widget: a rounded-corner card with a small inset of map
visible behind it, so the world never fully disappears. All chrome respects the
device safe area and does not intrude into the system status bar.

The mobile chrome changes how the workspace is *drawn*, never what it *is*: the
URL grammar, the tokens, and the navigation helpers are identical across form
factors. Each mobile surface below states which of its states live in the URL
and which are ephemeral view state.

**A course or an activity plan rides inside the nav widget on a narrow
screen.** Both render in the widget's expandable cavity over the scoped map
(the Google Maps "map + sheet" pattern, with the rail icons anchored beneath),
not as a separate sheet or a full-screen page — dragging the widget up reveals
the full content. A **course card** opens at the collapsed peek, the scoped map
leading; an **activity plan** opens at **half height with the camera settled on
its pin**, so the learner sees where the activity lives while reading it —
swipe up for the full plan. On a wide screen the same content is a bounded
panel beside the map. Only the *launched session* — a live chat — is a
full-screen surface (see *Full-screen surfaces* below).

The widget remembers its height **per course** (and per activity): opening a
chat over it tears it down, and closing that chat reopens it at the size the
learner left *that* course at, while a different course still opens at the
collapsed peek. The memory is scoped to the content, not global, so one
course's expanded widget never dictates the next course's opening size (#7332).

**Tapping a map pin promotes it; there is no preview popup.** Tapping a small or
mid pin expands it to its **large card in place** (over the map, the bottom nav
still showing); tapping a large card opens the activity's **plan page**. Tapping
the empty map collapses a promoted card. The large-card design lives in
[world-map.instructions.md](world-map.instructions.md).

### Single-column bottom nav
[Mobile_UI_component](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13126-42905&t=NJSsG23tsR9Kdwlz-0)

In single-column mode the side rail is replaced by a **floating rounded-corner nav
widget** pinned to the bottom of the safe area. The entire structure — rail and
expandable content — lives inside one rounded-corner box (styled similarly to the
web rail, but horizontal and contained; think Instagram's bottom bar but with an
expandable cavity above it).

**Collapsed state (rail only).** The widget shows only the 4-item nav rail. Items
are, left to right: **World**, **Chats**, **Courses**, and a **course shortcut**.
The course shortcut resolves contextually: the `+` add-course button when no
courses are joined, the single course avatar when exactly one course is joined, or
the most-recently-opened/tapped course otherwise. This mirrors the web rail's
order and function. The most-recent choice is device-local view state, never part
of the URL; the other joined courses are reached through the Courses list.

**Expanded height.** Tapping a rail item is the same navigation as the
web rail — it replaces the open left panels with that section's token
(`left=chats`, the Courses hub, the course card under `?c=`) — and expands the
widget upward, filling the upper portion of the rounded box with that
section's content. The **chats sheet and the Courses hub open content-fit**:
just tall enough to show all their rows — all chats, or all joined courses (the
add-course buttons when there are none) — capped by the height available below
the analytics bar (a short list yields a short sheet; a long one fills to the
cap and scrolls). Other sections open at roughly half the screen. The 4 rail
icons remain anchored at the bottom of the widget at all heights. Content inside
the expanded area is **scrollable**.

**The Courses hub header carries the add-course actions.** With at least one
joined course, the three add-course actions (start my own / enter a code /
browse public) ride the panel header as compact right-justified icons, so the
joined-course list keeps the vertical space; when the learner is in no courses
yet they drop to full-width buttons in the body as the empty state.

**The chats sheet header carries its actions**: an expanding **search
toggle** (an icon; tapping it reveals the filter field, autofocused — the
field is not always-on because vertical space is the sheet's scarce resource)
and the **new-chat action** (formerly a floating Direct Message FAB, which
covered the bottom list rows).

**The URL carries the panel, not the geometry.** The widget's height — collapsed,
half, full — is ephemeral view state, exactly like fold recency above: a cold
link or a refresh with an open **section** token (the chat list, the Courses
hub) or an **activity plan** draws it expanded at its default rest height (the
leaf rule) — content-fit for the list sections (the chat list, the Courses
hub), roughly half otherwise; a **course card** draws at its remembered height —
the collapsed peek by
default (see the per-course memory above), so the scoped map leads. The
collapsed rail over the bare map is just `/`. A shared URL never encodes how
far someone had dragged a sheet.

**Expanded to full height.** A **drag handle** at the top of the expanded content
lets the user pull the widget to full height: it grows until the search bar
riding above it sits immediately below the analytics bar — the rail icons, the
search bar, and the analytics bar all stay visible and tappable at maximum
extent. The widget does not grow past that bound regardless of how much content
it contains. The handle is also a labeled button — a tap toggles half ↔ full —
so the resize is reachable without a drag gesture (keyboard / switch access;
the #7128 pattern).

**Collapsing is not closing.** Tapping outside the widget or tapping the
already-active rail item collapses it back to the rail-only state — ephemeral:
the panel tokens stay in the URL, the rail highlight stays put, and tapping the
item again re-expands what was open (the single-column rule above — panels stay
in the URL, just not drawn). The **X** in the expanded cavity's header is the
panel's real close: it drops the token, exactly like the same panel's X on web.
Navigating into a full-screen surface also collapses the widget.

**System back follows the workspace history.** The Android / browser back button
undoes the last token navigation — closing what was opened, restoring what was
closed (see [History follows the workspace](#history-follows-the-workspace)).
The ephemeral expand/collapse of the widget is never a history entry.

**Full-screen surfaces.** A live chat room — including a launched activity
session — opens full-screen, covering the nav widget: **full-bleed, edge to
edge** — no card chrome, no map inset — because on a phone every pixel of a
chat matters (#7554; the surface's own app bar absorbs the status-bar inset,
and the composer reaches the keyboard with no floating gap below). This is a
render fact only — the token, allocator slot, and history behave exactly as
before. The nav widget is not accessible while one of these surfaces is
focused. (The activity *plan* is not one of
these — it rides the cavity at half height, its pin visible above.)
**Route-driven center-detail pages** — a course-wizard step, a public-course
preview, a chat archive, the new-private-chat form — are full-screen surfaces
too: they are task flows carrying their own app-bar navigation, so the nav
widget hides and no analytics chrome shows at all (they neither inset below
the bar the way right panels do, nor share the screen with floating chrome —
see the surface table under
[Single-column analytics nav bar](#single-column-analytics-nav-bar)).

**The 4 rail items, opened (Figma):**
- [World default state](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13369-63515&t=NJSsG23tsR9Kdwlz-0)
- [Chat list](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13394-61038&t=NJSsG23tsR9Kdwlz-0)
- [Courses list](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13394-61048&t=NJSsG23tsR9Kdwlz-0)
- [Active course](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13394-61069&t=NJSsG23tsR9Kdwlz-0)

### Single-column analytics nav bar
[Default component](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13372-94063&t=NJSsG23tsR9Kdwlz-0)

In single-column mode the cluster's vertical powerups column becomes a
**horizontal analytics bar** pinned to the top of the safe area. Layout
differences from the web cluster:

- The **level badge and the powerups pill are one unit** — the web cluster's
  pill turned horizontal: the badge overhangs the pill's LEFT end, and the
  pill's frame **is the XP ring**, gold progress growing clockwise from the
  top of the badge around the pill and meeting back at the badge's bottom.
- **Avatar** sits to the right of the bar, in the same spot as web (no ring of
  its own while the pill carries the XP).
- **Flag** sits below the avatar, slightly smaller than on web and with less
  spacing.
- **Stars, Grammar, and Vocabulary trackers** remain as tappable controls in
  the pill.

**Where the bar shows, per surface.** The bar is *analytics navigation*, so it
appears where it navigates and never floats over a page that has its own
navigation. It has exactly two renderings — the **full bar** and the
**avatar** (the circle wearing the XP ring, level badge, and L2 flag — the
Figma
[collapsed component](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13372-100160&t=NJSsG23tsR9Kdwlz-0)) —
and the avatar is **hosted inside the chat's own app bar** as a trailing
action, never floated over content (stacked chrome proved error-prone; a
floating timed expansion was also a WCAG liability, so the avatar is a plain
button that opens the analytics summary panel — whose header is the full bar).

| Surface | Bar |
| --- | --- |
| Bare world map | Full |
| Cavity surfaces (chat list, Courses hub, course card, activity plan) | Full |
| Map pin preview sheet | Full |
| Right panels (analytics summary/tabs, word/grammar details, settings) | Full — the bar IS their navigation and heads them |
| Live chat room / launched activity session / session review | Avatar, in the chat's app bar |
| Route-driven detail pages (course wizard, public-course preview, chat archive, new DM form) | None — they carry their own app-bar navigation |

**Single-column mutual close.** Sibling-closing is per-column on web, but on
one column a SECTION sheet (the chat list, the Courses hub, a course card, an
activity plan) and a right panel (analytics, settings) are peers in the same
visual slot — so opening one closes the other at navigation time: a bar tap
drops the open section tokens, and a rail tap drops the right list. Without
this, X-ing the panel revealed a stale sheet instead of the map. A live
`room`/`session` is NOT a section and persists under a right panel — the
header-avatar loop (chat → analytics → X → back to the conversation) depends
on it. Column mode is untouched: both columns coexist there.

**Expanded state.** Tapping a bar element opens the same right-column tokens as
the web cluster (`right=analytics:vocab`, `right=settings`, the level tab, the
flag's learning-settings shortcut) — the mobile panel is the single-column
rendering of the right column, so a shared or refreshed URL restores it like any
other panel. It fills the width (minus the floating-chrome margins) on every
single-column screen, per the Figma frames — no fixed width cap; if a large
tablet stretches it awkwardly, bound it then. Its leading control follows the
[close-affordance rule](#closing-a-panel-x-or-back-arrow) and sits at the top of
the screen **in line with the analytics bar** (chrome, not panel content): an
**X** on a summary (dropping the token), a back arrow once a page is pushed
(Security → a leaf). Each expanded panel carries its **own search bar** directly
below the analytics bar, scoped to its content — Search Vocab / Grammar /
Activities / Settings, per the Figma states. The panel content expands upward
from the bottom, covering the bottom nav widget completely — the nav rail is
not accessible while an analytics or settings panel is open, even when there is
not enough content to physically reach the nav widget. The analytics bar itself
remains visible at the top throughout. This is the key behavioral distinction
from the bottom nav's own expanded state, in which the rail icons always remain
visible. The settings panel renders the **existing settings surface** in this
chrome; the reorganized settings content some frames show (inline language /
CEFR pickers) is a separate design effort, not part of the chrome.
[Analytics section](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13485-90933&t=NJSsG23tsR9Kdwlz-0)
[Wider tablet analytics](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13377-63983&t=NJSsG23tsR9Kdwlz-0)


### Single-column search bar

In single-column mode the search bar moves from its top-left web position to a
**floating bar pinned above the bottom nav widget**, approximately 8px above the
rounded nav container. It sits outside the rounded nav box and **rides upward as
the widget expands**, maintaining that gap; at the widget's full height it sits
immediately below the analytics bar (the widget's growth bound is defined so the
bar never overlaps the avatar or analytics bar). **Map filters**, when active,
appear above the search bar (rather than below) and ride and minimize with it.

**The bar searches what is open.** Over the bare map it is the activity search
("Search Pangea"); with a section expanded in the widget it re-targets to that
section's content — the chat list ("Search All chats"), the courses list
("Search Courses") — per the Figma states. One persistent bar, contextual
scope: on narrow the bar **subsumes** a section's own search field (the chat
list's inline search hides; the floating bar drives it), so two search fields
never show at once. An expanded section always wins over the course-scoped
minimize below — the bar minimizes only over the bare scoped map.

**Default (visible).** The search bar is visible above the nav widget at all
section roots while the map is not being actively scrolled.
[Default component](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13126-44560&t=NJSsG23tsR9Kdwlz-0)

**Scroll / course-scoped minimized.** When the user begins scrolling the map with
the nav widget collapsed, or while the workspace is course-scoped (`?c=` set),
the search bar and its active filters **minimize to a compact search icon
button** pinned to the left side just above the nav rail. Tapping it restores
the full bar. **Once the course card itself is pulled to full height it covers
the map, so the bar hides entirely** — its reserved strip is handed to the
course content, and the compact button reappears when the sheet is dragged back
below full (#7697).
[Minimized component](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13126-44562&t=NJSsG23tsR9Kdwlz-0)

**Keyboard behavior.** When the search bar is active and the software keyboard
would push the bar out of view, the bar slides up to sit immediately above the
keyboard rather than being obscured.

## The surfaces

### How each surface opens

One entry point is canonical per surface, on every form factor, so the same tap
behaves the same on mobile and desktop.

| Surface | Opens from | Column | As |
|---|---|---|---|
| World map (home) | app root, World rail | the backdrop | always mounted; the World control clears every panel **and** the course context (the one full reset) |
| Course | a space in the rail, a map pin, a Courses-list tile | left + `?c=` | sets the course context and opens the `course` panel (master); tabs ride in the token param |
| A course management page (invite, edit, access, permissions, change-course) | the course card's More menu | left | opens as a `coursepage` detail **beside the card**, folding onto it only under width pressure — the same fit test as a settings page. Never replaces the card |
| Chat list | the rail | left | open panel (master) |
| Live chat / session | a chat-list row, an activity launch, **a course room row** | left | open panel (detail); one live view at a time. A course room rides over the course context (`?c=` stays), so closing it reveals the course |
| Chat members / settings (a regular chat) | the chat header | the chat panel | push (members/search live *within* the chat, not beside it) |
| Analytics (vocab / grammar / sessions) | a top-right cluster tracker (the **Stars** tracker opens the sessions panel) | right | open panel (master) |
| Level | the **level medal** on the powerups pill | right | open panel (an analytics tab) |
| A construct detail | tapping a vocab/grammar item | right | open panel (detail) beside its summary; **one detail at a time, across both columns** — a vocab detail, a grammar detail, and a completed-activity `session` review share ONE slot (a live `room` chat is independent and stays open); folds under pressure |
| Practice session | the **Practice** button on the vocab/grammar analytics panel; the live-session badge on that section's cluster tracker (resume) | right | a panel over a persistent background session — see [Practice](#practice-is-a-persistent-background-session) below |
| Profile + settings menu | the top-right cluster avatar | right | open panel (master) |
| A settings page (learning, style, security, …) | a settings-menu row | right | open panel (detail) beside the menu, folding only under width pressure — same fit test as a course management page |
| Learning settings (shortcut) | the cluster's **language flag** | right | opens the learning-settings page directly — the flag doubles as a shortcut to it |
| A settings leaf (password, blocked users, emotes, …) | within its settings page | the settings panel | push |
| Courses (your courses + add a course) | the **Courses** rail icon | left | open panel (master) — joined-course tiles plus the add-course options (start-my-own / browse / enter-code) |
| Activity plan | a course's activity list, a map pin (tap) | map content | a left-column `activity:<id>` panel over the map (the nav widget's cavity at half height on narrow, pin visible above), camera on its pin. It claims the single **live view** (a `liveView` sibling of `room`/`session`), so opening it drops any open chat and starting the session drops the plan; it sizes by the registry like a `room` (#7385). When the learner already holds an unfinished session, the bound session room rides in the token param so the plan offers resume instead of a fresh instance (#7257). Its close follows the [affordance rule](#closing-a-panel-x-or-back-arrow): with `?c=` set (opened from the course's activity list, or from a pin on the course-scoped map) a back arrow returns to the course card; with no context (a world-map pin, a standalone shared link) an X reveals the map. **Start** launches the session, which runs as a chat room (one live view) |

### One live session at a time

At most one **live view** is open at once. The Matrix room timeline is shared
rather than reference-counted, so two live views of a room would overwrite each
other. A live chat (`room` token) and a completed-activity review (`session`
token) both render that one live view, so opening either drops the other.

A completed activity session opens as its **actual chat**, locked from new
messages — the real timeline, with the wrap-up summary posted in it as a
message. It uses a distinct **`session`** token (rendered identically; the lock
is room-state driven) for one reason: a `session` belongs to the single **detail
slot** shared with the right-column vocab/grammar details, so opening a
construct detail closes an open session and vice versa, whereas a live `room`
chat is independent of that slot and coexists with an open detail. *(Future:
folding the choreographer controller into the chat controller would give rooms
their own session state and could lift the one-live-view limit.)*

### Practice is a persistent background session

Practice (the vocab/grammar exercise flow) is a right-column `practice` token —
a normal bounded panel, **not a route and not fullscreen**. Unlike other
panels, the session it runs is a **background activity that outlives its
panel**: leaving the panel loses nothing and ends nothing — the session runs
until it is explicitly ended or finished.

- **Leaving is free and silent.** Opening Settings, another analytics surface,
  or a rail section drops the `practice` panel from the URL but keeps the
  session alive in memory; re-opening practice resumes exactly where it left
  off. No confirm dialog on leave. Session state is ephemeral view state, never
  in the URL — a refresh or app restart starts fresh.
- **One session at a time.** A single practice session is live across both
  sections. Starting practice in the other section, or restarting the same
  one, **replaces** it — confirming first only if the current one is
  unfinished.
- **Ending is explicit and confirms.** The panel carries an **End session**
  control (the same leave affordance as leaving a chat); ending discards
  in-progress work, so it asks first. The panel's **X is just "leave"** —
  drops the panel, reveals what's beneath, never prompts.
- **The timer runs on wall-clock** from session start and keeps counting while
  the panel is closed. This is itself an anti-cheat mechanism: stepping out
  mid-session to consult a dictionary or an AI costs the clock, so the speed
  bonus rewards finishing unaided in one sitting.

**You can't study the answer key mid-exercise.** While a section's session is
live, that section's analytics is off-limits: its cluster tracker **resumes the
live practice instead of opening the analytics summary**, and the summary and
its construct (word/grammar) details don't open. This is why practice is no
longer modeled as a *detail of* the analytics master — it can't reveal the
surface it hides. The *other* section's analytics stays available. Definitions
reachable by other routes (a word card tapped in a chat message) are a known,
accepted gap, not a guarded path.

**The cluster shows a live session.** While practice is active, the section's
tracker in the top-right cluster (the horizontal analytics bar's pill on
narrow) wears a **badge — the practice icon and the running timer** — that
both signals the session and is the tap target that resumes it. It clears when
the session ends.

**It shares the cross-column detail slot.** Opening any construct detail or a
`session` review closes the practice panel (the session stays alive) and vice
versa; a live chat on the left is independent and stays open.

## The chrome

### The navigation rail

Pinned to the top-left of the map on web. Top to bottom: **World** (home),
**Chats**, **Courses**, then one avatar per joined course. Selecting a section
from it *replaces* the open left-column panels (see
[Panels are independent](#panels-are-independent)). On a narrow screen the rail
is replaced by the
[single-column bottom nav](#single-column-bottom-nav) widget.

**The selection highlight shows what you are looking at** — on the web rail and
the mobile widget's rail alike. Open left panels win: the highlight is the
section or course those panels belong to (`sectionFor`), so switching to Chats
moves the highlight to Chats even while `?c=` persists. When the left column is
empty, the highlight falls back to the backdrop — the course avatar under a
course context (you are looking at that course's map), World otherwise. The
context alone never out-highlights an open section.

### The cluster is the right column's entry point

A persistent cluster pinned to the top-right of the map opens the right column.
On a narrow screen the cluster becomes the
[single-column analytics nav bar](#single-column-analytics-nav-bar) — same elements,
same tokens, horizontal at the top.
It has its own gold **"powerups" visual** (per Figma), top to bottom: the user's
**avatar** wrapped in an XP ring (a gray track that fills gold clockwise toward
the next level, resetting on level-up); a gold **powerups pill** of three
trackers — total **Stars** earned, **Grammar**, **Vocabulary** — with the
**level medal** overhanging its base; and the active L2 **flag** below. The
Stars count is the learner's stars summed across activities, best per activity
(a replay doesn't multiply it), so it agrees with the per-pin fill on the map.

Each element is a labeled control (tooltip + semantic button label, since the
map is a canvas and gets no implicit labels): a **tracker** opens that metric as
a right-column panel — except while that section has a live practice session,
when it wears the practice badge and **resumes the session instead** (see
[Practice](#practice-is-a-persistent-background-session)); the **avatar** opens
the profile + settings master; the
**level medal** opens the Level analytics tab; the **flag** is a shortcut to the
learning-settings page. The flag shows the language's flag image, or its
uppercased **language code** when the language has no single regional flag (bare
`es` is ambiguous across regions; `es-ES` resolves to one). The cluster stays
pinned above the panels, because it is the anchor the right column justifies
against. Its live vocab/grammar counts and level/XP come from the analytics
streams — see
[analytics-system.instructions.md](analytics-system.instructions.md) for how a
UI surface reads them without missing the load-time update. The **Stars** count
comes instead from the learner's awarded-goal room state (the same source as the
[quest LO gate](quests.instructions.md)), so the cluster also rebuilds on that
room-state stream as goals are awarded.

## Cross-cutting

### History follows the workspace

The URL holds the workspace, so the back button, shared links, and reload all
move through the same state: opening a panel or pushing within one is a forward
step, and closing a panel or popping is a step back. Refocusing, reordering, a
width-driven fold or unfold, and the automatic transition a `launch` flag
triggers all *replace* the current history entry rather than adding one.
Product analytics mirrors these same steps — screen names derive from the token
lists and only history-adding navigations emit — see
[google-analytics.instructions.md](google-analytics.instructions.md).

### Adding a panel

Valid panels are listed in the [PanelTypeEnum](lib/features/navigation/panel_type_enum.dart). Each enum entry corresponds to a subclass of [PanelToken](lib/features/navigation/panel_token.dart), which contains a nullable subclass of [TokenParam](lib/features/navigation/token_params/token_param.dart), a class describing the panel's corresponding token param and containing parsing logic for any subpages or extra info the panel needs to render. Each PanelToken also has a corresponding subclass of [PanelDef](lib/features/navigation/token_params/panel_registry.dart), containing details about where and how the panel is rendered.
