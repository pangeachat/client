---
applyTo: "lib/config/routes.dart,lib/features/navigation/**,lib/widgets/layouts/**,lib/widgets/space_navigation_column.dart,lib/widgets/navigation_rail.dart,lib/widgets/mobile_bottom_nav.dart,lib/routes/world/**"
description: "How panels open, close and share the screen over the world map, and what the URL records."
---

# Client Routing & Workspace

Learners use panels that open over one world map, on any screen size. Outside links follow the org [deep-linking](../../../.github/.github/instructions/deep-linking.instructions.md) contract.

## The experience

1. The learner starts on the world map, with a rail of places and a cluster of their progress.
2. Choosing a course scopes the map to its activities and opens its card.
3. Panels open on the left or right, a detail beside its list.
4. Each panel closes with an X or a back arrow; the course collapses to a bar instead.
5. On a phone, the rail and cluster become bottom and top bars.

## Decisions

### Reading a workspace URL

- Only the URL records the scoped course and open panels, so links and refreshes restore them. Will.
- URLs stay readable to anyone on the team; only the app writes them, so old formats stop working. Will.
- Only the learner's moves add a Back step, so Back never undoes a panel the app hid for space. Will.

### The course context

- The course scope survives moving between panels; only another course, World (which also closes every panel), or leaving or deleting the course ends it, so closing panels shows its map. Will.

### Panels are independent

- Chats and courses open to the left, analytics and settings to the right, so a chat stays open beside analytics. Gabby.
- Closing one panel leaves the others open, so a learner can uncover the map and keep their chat. Choosing from the rail replaces only the left side. Gabby.
- A detail opens beside its list and covers it only when space runs out, so nothing closes to make room. Gabby.
- One live chat at a time, because two open copies of a chat overwrite each other. Gabby.

### Closing a panel: X or back arrow

- A back arrow goes up one level; an X closes to reveal what is underneath. Will.
- The course never closes: a chevron moves it between card and bar without moving its neighbor, so the map always names its course. Gabby.
- On a phone the chevron points where the sheet slides; on a wide screen, where nothing slides, down opens and up closes. Gabby.

### Every panel is a named group to assistive tech

- Screen readers announce each panel's name and read the map last, so learners reach the panels first. Gabby.
- A panel opened from the cluster or a rail course takes focus, so the next key press lands there. Gabby.

### Practice is a persistent background session

- Leaving practice keeps the session and its clock running, so looking up answers costs time; only ending asks to confirm. Gabby.
- During vocab or grammar practice, that tracker shows the timer and resumes practice instead of opening analytics, so learners cannot look up answers. Gabby.

### Single-column (narrow and mobile) mode

- Only the most recently opened panel shows, so a live chat never hides a new one. Gabby.
- A live chat fills the phone edge to edge, because every pixel of a chat matters. Gabby.

### Single-column bottom nav

- A link never records how far a sheet was dragged, and collapsing a sheet does not close it. Will.

### Single-column analytics nav bar

- In a chat the analytics bar becomes an avatar in the chat's header, because floating controls caused bugs and failed accessibility. Ava.
- On a phone, opening analytics or settings closes an open list, course card or activity plan, and the reverse, so closing one shows the map. Ava.

### Single-column search bar

- One floating bar searches whatever is open, so two search fields never show; in a course the course bar replaces it. Gabby.

### A chat's header actions

- The More menu offers every long-press action, because many learners never discover long-press. Gabby.

### A signed-out visitor's destination

- A signed-out visitor's last link opens once after sign-in; it expires so a shared browser cannot pass it on, and is never logged or reported. Will.

## Open questions

- Does a pushed page show X or back arrow (this doc) or both (the code)?
- Pin taps: this doc opened the plan on any tap and cleared focus on an empty-map tap; [world-map](world-map.instructions.md) disagrees on both.
- This doc counted four outside link shapes; is the gift link a fifth?
- This doc derived the two-column breakpoint from panel widths; the code fixes it.
- Does the phone's search bar shrink while the map scrolls? Only its filter bar does in the code.
- This doc gave each phone right panel a search bar; settings has none in the code.
