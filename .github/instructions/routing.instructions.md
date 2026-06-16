---
applyTo: "lib/config/routes.dart,lib/features/navigation/**,lib/widgets/layouts/**,lib/widgets/space_navigation_column.dart,lib/widgets/navigation_rail.dart,lib/widgets/mobile_bottom_nav.dart,lib/routes/world/**"
description: "Client routing & workspace design — the URL is the single source of truth for an ordered set of panels over a persistent map: columns by role, one shared-width budget, one live session at a time."
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
camera biases its focal content (a location, a course region, an activity) into
the uncovered area rather than the geometric center.

## The URL is the workspace

The URL carries two ordered panel lists, a **left** list and a **right** list;
order is left-to-right placement. Everything the shell renders is derived from that
one place, so the page builders and the chrome (rail, bottom nav) cannot disagree
about what is open. Internal navigation builds these URLs through the canonical
route builders; external, push, and `matrix.to` links are rewritten inbound to
canonical workspace URLs and are never emitted internally.

## Panels are independent

Each open surface — the chat list, a live chat, a course, settings, the analytics
summary, a vocab or grammar detail, a completed-activity review — is its own panel
with its own close. Closing one leaves the rest open, and navigating changes which
panel is focused instead of tearing down what is already open, so a learner can
close the chat list but keep the chat, or move to the world and keep the chat.

## Two columns, taken by role

A panel's side is decided by its **role**, not its content:

- **Left** — navigation and social surfaces (chat list, a live room, a course,
  settings). Justified to the left edge.
- **Right** — personal learning and review (analytics summary, a vocab or grammar
  detail, a completed-activity review). Justified to the right edge, so a summary
  rests at the edge and its detail opens to the left of it.

Because role decides the side, the same room can be open on the left as a live
conversation and on the right as a completed-activity review at the same time.

## One shared width

Both columns draw from a single shared width:

- Each panel grows greedily to a **maximum — about 720 by default, overridable per
  panel — because most content reads poorly much wider**. Width no panel takes
  stays uncovered map.
- When the open panels want more than fits, they **compress toward per-panel
  floors** (opaque content like a chat or a detail has a real minimum; the map
  absorbs the slack as the backdrop), and only then does the **lowest-priority
  panel collapse to a peek or tab**. There is no full-screen takeover.
- **Width is the only canvas concept.** An empty center is the absence of a panel;
  a bounded panel is the default; a full-bleed surface is a panel that raises its
  maximum to the viewport; and a surface that must hold the screen alone marks
  itself **exclusive**, collapsing the others while it is open (an in-progress
  activity is the main example).
- **Narrow screens are the degenerate case of the same rule**, not a separate
  layout: the chrome swaps (the side rail becomes bottom navigation, the left inset
  goes to zero) and the focused column's top panel seats full while the rest peek.

## One live session at a time

At most one **live** chat or activity session is open at once. The Matrix room
timeline is shared rather than reference-counted, so two live views of a room
overwrite each other. A **read-only review** of a completed session opens no
timeline, so it may coexist with a live session and with a review of a different
room. Opening a new live session replaces the current one. *(Future: give a room
its own session state by folding the choreographer controller into the chat
controller, which would lift this limit.)*

## The cluster is the right column's entry point

A persistent cluster pinned to the top-right of the map opens the right column: the
user's avatar ringed by experience progress and level, their target-language flag,
and trackers for completed sessions, grammar, and vocabulary. Tapping a tracker
opens that metric as a right-column panel, and its detail blooms to the left. The
cluster stays pinned above the panels, because it is the anchor the right column
justifies against.

## History follows the workspace

The URL holds the workspace, so the back button, shared links, and reload all move
through the same state: opening a panel is a forward step and closing it a step
back, while refocusing, reordering, or an automatic collapse replace the current
entry rather than adding history.

## Adding a panel

A new surface is a registry entry, not a new route tree: declare its column (which
fixes its role and justification), its minimum and maximum width, its collapse
priority, and whether it is exclusive. The parser, the width allocator, and the
chrome pick it up from there.
