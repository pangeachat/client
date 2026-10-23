---
applyTo: "lib/config/routes.dart,lib/features/navigation/**,lib/widgets/layouts/**,lib/widgets/space_navigation_column.dart,lib/widgets/navigation_rail.dart,lib/widgets/mobile_bottom_nav.dart,lib/routes/world/**"
description: "How panels open, close and share the screen over the world map, and what the URL records."
---

# Client Routing & Workspace

The app is a workspace of panels over one world map, for learners on every screen size. Outside links follow the org [deep-linking](../../../.github/.github/instructions/deep-linking.instructions.md) contract.

## The experience

1. The learner starts on the world map, with a rail of places and a cluster of their progress.
2. Choosing a course scopes the map to its activities and opens its card.
3. Panels open on the left or right, a detail beside its list.
4. Each panel has one way out, X or a back arrow; the course collapses to a bar instead.
5. On a phone, the rail and cluster become bottom and top bars and one panel shows at a time.

## Decisions

### Reading a workspace URL

- Only the URL records the scoped course and open panels, so links and refreshes restore them. Unassigned.
- URLs stay readable to anyone on the team. Only the app writes them, so retired shapes are dead links, a call at current scale ([#7467](https://github.com/pangeachat/client/issues/7467)). Unassigned.
- Only the learner's own moves add a Back step, so Back never undoes an automatic fold. Unassigned.

### The course context

- The course scope survives all navigation until another course, World (which clears every panel) or leaving it, because closing panels reveals its map. Unassigned.

### Panels are independent

- Chats and courses open left, analytics and settings right, so a chat stays open beside analytics. Unassigned.
- Each panel closes alone, so clearing the map never loses a chat; a rail section replaces the left column. Unassigned.
- A detail opens beside its list and folds onto it only when space runs out, using the screen without closing anything. Unassigned.
- One live chat at a time, since two views of one room overwrite each other. Unassigned.

### Closing a panel: X or back arrow

- The control follows what is on screen, not where the learner came from, so a shared link shows the same one. Unassigned.
- The course never closes: a chevron moves it between card and bar (a phone's peek) without moving its neighbour, so the map always names its course. Unassigned.
- On a phone the chevron points where the sheet moves; on wide it follows show/hide, since nothing moves. Unassigned.

### Every panel is a named group to assistive tech

- Screen readers hear each panel's name and reach the map last, so no panel sits behind it. Unassigned.
- A panel opened from the cluster or a rail course takes focus, so the next key press lands there. Unassigned.

### Practice is a persistent background session

- Leaving practice keeps the session and its clock running, so looking answers up costs time; leaving never asks, ending does. Unassigned.
- While a section's practice is live, its tracker shows the timer and resumes practice instead of opening analytics, so learners cannot study the answer key. Unassigned.

### Single-column (narrow and mobile) mode

- One panel shows, the most recently opened, so a live chat never hides one just opened. Unassigned.
- A live chat fills the phone edge to edge, because every pixel of a chat matters. Unassigned.

### Single-column bottom nav

- Sheet height stays out of the URL, so a link never encodes a drag; collapsing a sheet is not closing it. Unassigned.

### Single-column analytics nav bar

- In a chat the analytics bar shrinks to an avatar in its header, because floating chrome proved error-prone and timed expansion failed accessibility. Unassigned.
- A section sheet and a right panel close each other, so closing one never reveals a stale sheet. Unassigned.

### Single-column search bar

- One floating bar searches whatever is open, so two search fields never show; in a course the course bar replaces it. Unassigned.

### A chat's header actions

- The More menu offers every long-press action, because many learners never discover long-press. Unassigned.

### A signed-out visitor's destination

- A signed-out visitor's last link survives sign-in once, landing them where it pointed; it expires so a shared browser cannot pass it on. It is never logged or reported. Unassigned.

## Open questions

- Does a pushed page show X or back arrow (this doc) or both (the code)?
- Pin taps: this doc opened the plan on any tap and cleared focus on an empty-map tap; [world-map](world-map.instructions.md) disagrees on both.
- This doc counted four outside link shapes; is the gift link a fifth?
- This doc derived the two-column breakpoint from panel widths; the code uses a fixed width.
- Does the phone's search bar shrink while the map scrolls? Only its filter bar does in the code.
- This doc gave each phone right panel a search bar; settings has none in the code.
