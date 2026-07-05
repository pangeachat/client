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
  one token per open panel, ordered **first beneath, second on top** (master
  first for a master/detail pair — the full rule is below).
- A token is **`type:param`**. The type names the surface (`chats`, `room`,
  `course`, `settings`, `analytics`, `vocab`, `activity`, …); the param carries
  the panel's identity and active tab, plus any page pushed within the panel
  after a `/`.

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

**Compatibility.** The parser is tolerant — it normalizes a registry
master/detail pair to master-first whatever order an old link carries (the
[panel registry](../../lib/features/navigation/panel_registry.dart) knows which
type is whose master), keeps the given order for pairs the registry does not
relate, and accepts older token spellings — and
[`LegacyRedirects`](../../lib/features/navigation/legacy_redirects.dart) rewrites
old shapes (path forms, `?m=course:<id>`, loose params like `activity=` and
`launch=`) before anything renders. Old bookmarks and shared links keep working forever;
internal navigation emits only the canonical form above.

## The core model

### The URL is the workspace

The context param and token lists are the sole source of what renders — nothing
draws from the path, which always collapses to `/`. The page builders and the
chrome (rail, bottom nav, cluster) all derive from the same tokens, so they
cannot disagree about what is open. Closing a panel is just dropping its token:
there is no second, path-driven copy to leave standing.

Paths survive only as an **inbound shape**, never a render source: external,
push, and `matrix.to` links — including the `/rooms/:roomid` shape they carry —
are rewritten to canonical token URLs at the router redirect *before* anything
renders, so there is exactly one representation by the time the shell builds.

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
changes in exactly two ways: selecting another **course** replaces it, and the
**World/home** control clears it — the one deliberate full reset, dropping every
open panel *and* the context together in one history step so the back button
restores both. Surfaces that carry no context of their own (the Courses hub,
Chats, Settings) overlay the map you left without changing it.

Pure **map filters** (region, language, activity kind) are a future, separate
`?m=` list — display refinement, not workspace context. Nothing uses it today;
legacy `?m=course:` links rewrite to `?c=`.

### Navigate by token

Internal navigation MUST go through the
[`WorkspaceNav`](../../lib/features/navigation/workspace_nav.dart) token helpers
(or the token-producing `PRoutes` builders) — `setSection`, `openSettings`,
`openCoursePage[For]`, `openConstructDetail`, `closeLeft`, and friends. Two
smells, both forbidden in feature code:

- **A path literal in a `.go(...)`** (`/chats`, `/rooms/settings/...`,
  `/courses/:id/...`). Section, room, and course paths exist only as legacy
  redirect shims for inbound links we don't control; an internal path navigation
  just bounces through the redirect — a wasted hop, and exactly how the
  dead-`/chats` bug (#7067) happened. This includes the standalone activity link
  `/<uuid>`: it too is an inbound shim, so in-app code opens activities through
  the token helpers, never by emitting the path.
- **Hand-editing the query string.** Panels never assemble or sweep query params
  themselves; the query-editing utilities are internal to the navigation layer.
  If a surface needs a navigation the helpers can't express, add a helper — that
  keeps the grammar in one place.

The only legitimate path destinations, all declared in `routes.dart`: the
fork-inherited `/rooms/...` utility pages (archive, new-chat flows, …) that have
not yet joined the token model; the pre-login and utility routes (`/home`,
`/onboarding`, `/registration`, `/logs`, `/configs`); the route-driven Completer
flows (`/courses/own/:courseid[/invite]`, `/courses/:spaceid/addcourse/:courseId`);
and the public-course preview. `/rooms/:roomid` itself is an inbound shape (the
contract push and `matrix.to` links arrive on), rewritten to a `room` token
before render. `PRoutes`'s `chats`/`analytics`/`settings`/`profile`/`rooms`
constants are legacy section paths — redirect sources and `sectionFor`
identities, never navigation targets.

**Inbound loose params fold into tokens at the boundary.** Links from outside
the client may arrive with loose query params — `activity=`, `roomid=`,
`launch=`, `autoplay=` (the accepted shapes live in
[deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md)).
`LegacyRedirects` folds every one of them — identity and behavioral flags
alike — into the target panel's token param before anything renders. Past the
redirect there are no loose params: a panel reads everything it needs from its
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
breakpoint (narrow windows; phones always) the chrome swaps — the side rail
becomes bottom navigation — and only one panel shows: the
**most-recently-opened** one, so opening a panel always brings it forward.
Recency is ephemeral view state, not part of the shareable URL; on a cold link
or a refresh the shown panel falls back to the active **leaf** of the tree (a
child over its parent, ties broken by priority). Recency matters because
priority alone would let a live chat silently out-rank a freshly opened settings
or analytics panel. The other panels stay in the URL, reopened from the chrome,
so nothing is lost — just not drawn at once. Every master/detail flow is already
folded here: one panel, navigated with a back arrow.

**Map content folds to a bottom sheet on a narrow screen.** A surface that is
*map content* — a course, an activity plan, or the add-course flow — renders,
when it is the focused narrow surface, as a draggable bottom sheet over the
scoped map rather than a full-screen page (the Google Maps "map + sheet"
pattern), so the map stays visible above it. Dragging the sheet up reveals the
full content. On a wide screen the same content is a bounded panel beside the
map.

**Tapping a map pin promotes it; there is no preview popup.** Tapping a small or
mid pin expands it to its **large card in place** (over the map, the bottom nav
still showing); tapping a large card opens the activity's **plan page**. Tapping
the empty map collapses a promoted card. The large-card design lives in
[world-map.instructions.md](world-map.instructions.md).

**The narrow bottom nav is only the section switcher** — World, Chats, and the
course switcher (Analytics and Profile are reached from the cluster, not here).
It shows only at a section root: the bare map, the chat list, or the courses
list. A focused detail hides it, and a bottom sheet (a course, an activity plan)
replaces it. The bar is present only when you are choosing *where* to go, never
while you are *in* something.

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
| Practice session | the **Practice** button on the vocab/grammar analytics panel | right | exclusive detail that folds the analytics master — see [Practice](#practice-is-an-exclusive-detail-of-analytics) below |
| Profile + settings menu | the top-right cluster avatar | right | open panel (master) |
| A settings page (learning, style, security, …) | a settings-menu row | right | open panel (detail) beside the menu, folding only under width pressure — same fit test as a course management page |
| Learning settings (shortcut) | the cluster's **language flag** | right | opens the learning-settings page directly — the flag doubles as a shortcut to it |
| A settings leaf (password, blocked users, emotes, …) | within its settings page | the settings panel | push |
| Courses (your courses + add a course) | the **Courses** rail icon | left | open panel (master) — joined-course tiles plus the add-course options (start-my-own / browse / enter-code) |
| Activity plan | a course's activity list, a map pin (tap) | map content | a left-column `activity:<id>` panel over the map (a bottom sheet on mobile), camera on its pin. It claims the single **live view** (a `liveView` sibling of `room`/`session`), so opening it drops any open chat and starting the session drops the plan; it sizes by the registry like a `room` (#7385). When the learner already holds an unfinished session, the bound session room rides in the token param so the plan offers resume instead of a fresh instance (#7257). Its close follows the [affordance rule](#closing-a-panel-x-or-back-arrow): with `?c=` set (opened from the course's activity list, or from a pin on the course-scoped map) a back arrow returns to the course card; with no context (a world-map pin, a standalone shared link) an X reveals the map. **Start** launches the session, which runs as a chat room (one live view) |

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

### Practice is an exclusive detail of analytics

Practice (the vocab/grammar exercise flow) is a right-column `practice` token —
a normal bounded panel, **not a route and not fullscreen**. Two rules make it
feel immersive:

- **It always folds its master.** Practice is a detail of the analytics master,
  but it folds analytics behind it even when width allows — the one deliberate
  exception to "fold only under width pressure", because browsing analytics
  beside a live exercise session would defeat the exercise. The master stays in
  the URL one back-step away, so **backing out of practice returns to the
  analytics page it came from, on every width**. (Practice must never *close*
  its master outright — that is what left `practice:morph` with no way back.)
- **It shares the cross-column detail slot.** Opening any construct detail or a
  `session` review closes practice and vice versa, and tapping the cluster's
  analytics replaces the whole right column. A live chat on the left is
  independent and stays open.

Backing out mid-session **confirms first** (unsaved exercise progress); a
completed or errored session doesn't re-prompt. Abandoning practice by opening
analytics from the cluster does not prompt — that path just replaces the right
column.

## The chrome

### The navigation rail

Pinned to the top-left of the map on web; the bottom nav on mobile. Top to
bottom (or left to right): **World** (home), **Chats**, **Courses**, then one
avatar per joined course. Selecting a section from it *replaces* the open
left-column panels (see [Panels are independent](#panels-are-independent)).

**The selection highlight shows what you are looking at.** Open left panels
win: the highlight is the section or course those panels belong to
(`sectionFor`), so switching to Chats moves the highlight to Chats even while
`?c=` persists. When the left column is empty, the highlight falls back to the
backdrop — the course avatar under a course context (you are looking at that
course's map), World otherwise. The context alone never out-highlights an open
section.

### The cluster is the right column's entry point

A persistent cluster pinned to the top-right of the map opens the right column.
It has its own gold **"powerups" visual** (per Figma), top to bottom: the user's
**avatar** wrapped in an XP ring (a gray track that fills gold clockwise toward
the next level, resetting on level-up); a gold **powerups pill** of three
trackers — total **Stars** earned, **Grammar**, **Vocabulary** — with the
**level medal** overhanging its base; and the active L2 **flag** below. The
Stars count is the learner's stars summed across activities, best per activity
(a replay doesn't multiply it), so it agrees with the per-pin fill on the map.

Each element is a labeled control (tooltip + semantic button label, since the
map is a canvas and gets no implicit labels): a **tracker** opens that metric as
a right-column panel; the **avatar** opens the profile + settings master; the
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

A new surface is a registry entry, not a new route tree: declare its column
(which fixes its role and justification), its place in the navigation tree (its
**parent** type, or none for a root; any **sibling groups** it shares a slot
with), its three widths (max, reasonable min, hard min), its tiebreak priority,
whether it is exclusive, and whether it opens its detail as a panel or pushes
it. The parser, the width allocator (fold), the close affordance, and the
single-column focus all read the same entry, so a correct tree placement is what
makes a surface fold, close, and focus right. A settings or profile page is just
a right-column entry whose parent is the settings menu and whose deeper levels
are reached by a push.
