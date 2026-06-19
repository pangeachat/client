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
close, and closing one leaves the rest open (close the chat list but keep the
chat; close a course to widen the map while the chat stays open). Selecting a
section from the **left nav rail** (chats, a course, the courses list)
**replaces** the open left-column panels with that section rather than stacking
beside them — clicking around the rail swaps what's on the left instead of piling
panels up — while the right-column companions (analytics, a detail) stay open.
The one deliberate clear-everything is the **World/home** button, which closes
all panels at once. (Opening a course from a map pin or a Courses-list tile is
navigating within your content, not a rail section switch, so it keeps an open
chat and swaps only the course.)

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
settings are personal account surfaces, so they belong on the right (they were
once route-driven in the left column; now they are a right-column `settings`
master with each page opening beside it as a `settingspage` detail).

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
degrade move: **fold**. A column's two panels collapse into one: the **child**
(detail) keeps the column, and its **parent** (master) folds behind it — not
drawn, one back-step away, revealed by closing the child — so the pair now costs
one panel's width (the parent/child/sibling tree below is what decides which is
which). Folding never discards a panel (both stay in the URL, so widening unfolds
back to two), and because the surviving panel is never torn down, a folded live
chat keeps its session.

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
bottom navigation, the left inset goes to zero — and only one panel shows: the
**most-recently-opened** one, so opening a panel always brings it forward (a child
opened over its parent, or a right-column panel opened over a live chat). This is
ephemeral view state, not part of the shareable URL — so on a cold link or a
refresh (no recency to consult) the shown panel falls back to the active **leaf**
of the tree (a panel no open panel names as parent, so a child shows over its
parent; ties broken by priority). Plain priority alone is *not* enough here: a
live chat out-ranks most panels, so a freshly-opened settings/analytics panel
would silently lose to it — hence the recency signal. The others stay in the URL,
reopened from the persistent chrome (the rail or bottom nav for a section, the
cluster for analytics), so nothing is lost, just not drawn at once. Every
master/detail flow is already folded here: one panel, navigated with a back arrow.

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
  longer honor reasonable-min widths, a column's **parent** (master) **folds**
  behind its **child** (detail) — not drawn, one back-step away — and **unfolds**
  back to two panels when width returns. A fold is a push the layout performs
  instead of the user.

### The navigation tree: parent, child, sibling

Every surface declares where it sits in one explicit tree (in the panel
registry), and the parser, the fold, and the single-column focus all read that
one structure — there is no separate priority or recency system to drift from it:

- A **child** declares its **parent** (the master it details). A child opens
  beside its parent when width allows and otherwise **stacks** on it (the parent
  folds behind the child). A `room` is the `chats` list's child; a settings page
  is the settings menu's child; a vocab/grammar detail is the analytics summary's
  child. A parent with no parent of its own is a **root** (a section master).
- **Siblings** are children that share one slot: they **can't coexist**, so
  opening one replaces the others. Vocab and grammar are siblings (one construct
  detail at a time); a live `room` and a `session` review are siblings (one live
  view). This is why grammar replaces vocab rather than stacking on it.

Most trees are two generations (chat list → chat; analytics → a construct
detail). A deeper level — security → change-password — is a **push within** the
child's own panel (its token param), not a third panel, so the panel-level tree
stays parent → child. **Priority is only a tiebreak** between independent trees
(which master folds first when several pairs are all under pressure; which leaf
is focused when independent panels are open). A child never folds and always
wins focus over its own parent regardless of priority.

**Opening is a fit test, not a depth count.** A surface opens a new panel when the
column is under its two-panel budget *and* the budget can grant the newcomer its
min width; otherwise the page **pushes** onto the panel it came from (back arrow).
Going deeper than a detail always pushes. Mobile has a one-panel budget, so every
open is a push — the fully-folded end of the same rule. A user push is a forward
history step and a pop is a step back; a width-driven fold/unfold *replaces* the
current entry, because an automatic relayout is not something the user should have
to "undo".

This is the rule for **every page that opens off a master**, and the two trees
that have one work identically: a **settings page** off the settings menu and a
**course management page** (invite, edit, access, change-course) off the course
card both open as a coexisting *detail* beside their master when width allows, and
fold to a push only under pressure. A detail page should never *replace* its master
outright — the master stays one step away (beside it, or folded behind it on a
narrow screen), so closing the page reveals the menu / card it came from. (A
regular chat's own members/search are the exception: they push *within* the chat,
because they belong to that one timeline, not beside it.)

**Map content folds to a bottom sheet on a narrow screen.** A panel that is *map
content* (marked `mapContent` in the registry — a **course**, and the add-course
flow) renders, when it is the focused narrow panel, as a draggable bottom sheet
over the scoped map rather than a full-screen panel — the Google-Maps "map +
sheet" pattern — so the map (a course's activity pins) stays visible above it,
with the cluster floating top-right. Dragging the sheet up reveals the full
content; an in-course chat or an activity opened from the course instead takes the
screen as its own panel / immersive surface. On a wide screen the same course is
an ordinary left panel beside the map.

**Tapping a map pin** opens its preview as a bottom sheet on a narrow screen
(the wide screen keeps the preview popup glued to the pin). The map owns that
transient selection, so it signals the shell (via a small controller) to hide the
bottom nav while the sheet is up, and the shell clears the selection when a
full-screen panel later covers the map (so the sheet doesn't linger).

**The narrow bottom nav is only the section switcher** — World, Chats, and the
course switcher (Analytics and Profile are reached from the cluster, not here). It
shows only at a section root: the bare map, the chat list, or the courses list. A
focused detail (a chat, a settings/analytics/construct page, a session) hides it,
and a bottom sheet (a course, a tapped pin) replaces it. So the bar is present
only when you are choosing *where* to go, never while you are *in* something.

## How each surface opens

One entry point is canonical per surface, on every form factor, so the same tap
behaves the same on mobile and desktop.

| Surface | Opens from | Column | As |
|---|---|---|---|
| World map (home) | app root, World rail | the backdrop | always mounted; the World button clears every panel |
| Course | a space in the rail, a map pin | left + `?m=` filter | sets `?m=course:<id>` (map scope) **and** opens the `course` panel (master); tabs ride in the token param |
| A course management page (invite, edit, access, permissions, change-course) | the course card's More menu | left | open panel (detail) **beside the card**, or pushed onto the card when folded — the same fit test as a settings page (a `coursepage` token; the card is its master). NOT a push that replaces the card |
| Chat list | the rail | left | open panel (master) |
| Live chat / session | a chat-list row, an activity launch, **a course room row** | left | open panel (detail); one live at a time. A course room rides over the course filter (`?m=course:<id>` stays) so closing it reveals the course |
| Chat members / settings (a regular chat) | the chat header | the chat panel | push (members/search live *within* the chat, not beside it) |
| Analytics (vocab / grammar / sessions) | a top-right cluster tracker | right | open panel (master) |
| Level | the **level medal** on the powerups pill | right | open panel (an analytics tab) |
| A construct detail | tapping a vocab/grammar item | right | open panel (detail), left of its summary; **one detail at a time, across both columns** — a vocab detail, a grammar detail, and a completed-activity `session` review share ONE slot, so opening any one closes the other two (a live `room` chat is independent and stays open); folds in under pressure |
| Practice session | the **Practice** button on the vocab/grammar analytics panel | right | open panel that **takes over the analytics surface** — see below. A normal bounded panel, NOT a route or fullscreen; its close confirms when a session is mid-progress |
| Profile + settings menu | the top-right cluster avatar | right | open panel (master) |
| A settings page (learning, style, security, …) | a settings-menu row | right | open panel (detail) beside the menu, or pushed onto the menu when folded — same fit test as a course management page |
| Learning settings (shortcut) | the cluster's **language flag** | right | opens the learning-settings page directly — the flag doubles as a shortcut to it |
| A settings leaf (password, blocked users, emotes, …) | within its settings page | the settings panel | push |
| Courses (your courses + add a course) | the **Courses** rail icon (Material map) | left | open panel — a flat list of joined-course tiles (image, name, participants, level, modules), with the add-course options (start-my-own / browse / enter-code) below; each option opens its step as the token param, deeper steps stay route-driven. Replaced the old float-over-the-map hub card that double-wrapped a card inside the panel |
| An in-progress activity | a course / the map | full-bleed | exclusive |

## One live session at a time

At most one **live view** is open at once. The Matrix room timeline is shared
rather than reference-counted, so two live views of a room overwrite each other.
A live chat (`room` token) and a completed-activity review (`session` token) both
render that one live view, so opening either drops the other.

A completed activity session opens as its **actual chat**, locked from new
messages — the real timeline, with the wrap-up summary posted in it as a message,
not a separate summary card. It uses a distinct **`session`** token (not `room`),
rendered identically (the lock is room-state, not token, driven), for one reason:
a `session` belongs to the single **detail slot** shared with the right-column
vocab/grammar details, so opening a construct detail closes an open session and
vice versa (one detail at a time across columns — see the construct-detail row
above), whereas a live `room` chat is independent of that slot and coexists with
an open detail. `openExclusiveSession` / `openConstructDetail` in `workspace_nav`
enforce this; `openExclusiveLeftRoom` (a live chat) drops room+session but leaves
the right column untouched. *(Future: give a room its own session state by folding
the choreographer controller into the chat controller, which would lift the
one-live-view limit and could let a completed session open as a coexisting
read-only review.)*

## Practice takes over the analytics surface

Practice (the vocab/grammar exercise flow) is a **right-column panel like any
other** — a `practice` token, a normal bounded card, **not a route and not
fullscreen**. What makes it special is exclusivity: a practice session **takes
the place of the analytics surface**. Opening it (the Practice button on the
vocab/grammar analytics panel, via `openPractice`) closes the `analytics` master
and any open vocab/grammar detail, and **while a session is active those cannot
be viewed beside it** — practice shares the single cross-column **detail slot**
(the same slot as the vocab/grammar details and a `session` review), so opening
any construct detail or a session closes practice and vice versa, and tapping the
cluster's analytics replaces the whole right column. So you are either *browsing*
your analytics (the master, optionally with one detail bloomed beside it) or *in*
a practice session — never both. This is an "immersive" scope, but only over the
analytics surface; a live chat on the left is independent and stays open.

Closing practice **confirms first when a session is mid-progress** (unsaved
exercise progress) — the panel's close reads `AnalyticsPractice
.bypassExitConfirmation`, which the session flips once it completes or errors. The
guard covers the explicit close; abandoning practice by opening analytics from the
cluster does not prompt (that path just replaces the right column).

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
- **The left rail is a floating dock pill.** The left nav rail floats as a
  `WorkspaceDock` pill (surface, elevation, `AppConfig.borderRadius`, outline
  border, clipped corners). It does **not** hover-expand; it stays a narrow pill
  (section/course names come from item tooltips and the Courses page's tiles), so
  the dock sizes to its icons. Order, top to bottom: **World** (home), **Chats**,
  **Courses** (the Material map icon, opening the courses list + add options),
  then an avatar per course you're in. The top-right cluster is its **own** gold
  "powerups" visual (next section), so the two edges no longer share one chrome —
  reuse shared constants (gold palette, radius), not one widget.

## The cluster is the right column's entry point

A persistent cluster pinned to the top-right of the map opens the right column. It
has its own gold **"powerups" visual** (Figma `AvatarLangFlags`), top to bottom:
the user's **avatar** wrapped in an XP ring (a gray track that fills gold clockwise
toward the next level, resetting on level-up); a gold **powerups pill** of three
trackers — completed **Sessions**, **Grammar**, **Vocabulary** — with the **level
medal** overhanging its base; and the active L2 **flag** below.

Each element is a labeled control (tooltip + semantic button label, since the map
is a canvas and gets no implicit labels): a **tracker** opens that metric as a
right-column panel (its detail blooms to the left); the **avatar** opens the
profile + settings master; the **level medal** opens the Level analytics tab (level
is analytics, reached from the medal — a placement that holds until level becomes
its own surface); the **flag** is a shortcut to the learning-settings page. The flag
shows the language's flag image, or its uppercased **language code** when the
language has no single regional flag (bare `es` is ambiguous across regions;
`es-ES` resolves to one). The cluster stays pinned above the panels, because it is
the anchor the right column justifies against. Its live counts/level/XP come from
the analytics streams — see
[analytics-system.instructions.md](analytics-system.instructions.md) for how a UI
surface reads them without missing the load-time update.

## History follows the workspace

The URL holds the workspace, so the back button, shared links, and reload all move
through the same state: opening a panel or pushing within one is a forward step and
closing a panel or popping is a step back, while refocusing, reordering, and an
automatic fold/unfold *replace* the current entry rather than adding history.

## Adding a panel

A new surface is a registry entry, not a new route tree: declare its column (which
fixes its role and justification), its place in the navigation tree (its **parent**
type, or none for a root; any **sibling groups** it shares a slot with), its three
widths (max, reasonable min, hard min), its tiebreak priority, whether it is
exclusive, and whether it opens its detail as a panel or pushes it. The parser, the
width allocator (fold), and the single-column focus all read the parent/sibling
links, so a correct tree placement is what makes a surface fold and focus right. A
settings or profile page is just a right-column entry whose parent is the settings
menu and whose deeper levels are reached by a push.
