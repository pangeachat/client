---
applyTo: "lib/config/routes.dart,lib/features/navigation/**,lib/widgets/layouts/**,lib/widgets/navigation_rail.dart,lib/widgets/mobile_bottom_nav.dart,lib/widgets/space_navigation_column.dart,lib/routes/world/**,lib/routes/courses/**,lib/routes/chat/activity_sessions/**,lib/routes/analytics/**"
description: "World v2 unified panel/routing architecture — one master/detail/push/fold mechanism over token-only URLs, declarative registry, generalized nav API, centralized close affordance, responsive panel↔sheet (desktop side-panel / mobile Google-Maps bottom sheet for map content). The active build plan; folds into routing.instructions.md when complete."
---

# World v2 — Unified Panel/Routing Architecture

The durable model lives in [routing.instructions.md](routing.instructions.md); this doc is the **one architecture** that removes every special-case and legacy workaround, and the build order to get there. Signed off by Will. When complete, the durable sections fold into `routing.instructions.md` and this file is deleted (along with that doc's "Migration plan (temporary)" section).

## One mechanism

Every surface is a **token** in the URL (`?left=` / `?right=` lists + the `?m=` map filter); the **path is always `/`**. A column holds a **master** and optionally one **detail**. Going deeper than a detail is a **push** encoded in the panel's own param. Under width pressure a column **folds** (master hides behind detail). Analytics, settings, courses, chat, and map selections are all instances — nothing special-cased.

## Declarative registry

`panel_registry.dart` is the single source of each panel type's behavior; the allocator, the chrome, the affordance, and the nav API all read it:

```
PanelDef {
  column,                 // left | right
  minWidth / reasonableMinWidth / idealWidth,
  priority,               // who folds first (higher survives)
  exclusiveGroup,         // panels mutually exclusive with each other:
                          //   'detail' = {vocab, grammar, session} (one detail across columns)
                          //   'liveView' = {room, session}        (one live timeline)
  pushable,               // hosts deeper pages in its param (settings, course, room)
  mapContent,             // a map selection → mobile: pin peek popup + bottom sheet;
                          //   non-mapContent detail → mobile: full-screen push
}
```

Adding a surface = one registry entry + one renderer. No new route tree, no bespoke nav function.

## Generalized nav API

`WorkspaceNav` collapses the per-surface zoo (`openSettings`, `settingsBack`, `openCourse`, `openConstructDetail`, `openExclusiveSession`, `openExclusiveLeftRoom`, `setSection`) into:

- `openMaster(token)` — set a column's master (drops the old section master; keeps the live view + the other column).
- `openDetail(token)` — open/replace the detail; enforces the registry `exclusiveGroup` (one detail across columns, one live view) generically.
- `pushPage(panel, page)` / `popPage(panel)` — a deeper page in the panel's param (settings leaf, course details/invite, room members/search).
- `close(token)` — drop it.

Exclusivity, side (column), and fold all derive from the registry, so rules cannot drift per call site.

## Responsive rendering — same token, three presentations

Breakpoint: `FluffyThemes.isColumnMode` (~832px) splits wide vs narrow.

| Breakpoint / interaction | Master | Detail (item / page) | Map content (pin, course, add-course) |
|---|---|---|---|
| **Wide** | column panel | side panel beside master; folds under pressure | side panel (≤600px), map peeks right |
| **Narrow** | full-pane list / the map | full-screen push | **pin peek popup → draggable bottom sheet** (peek/full) |

- `MobileDetailSheet` (generalizes `MobileCourseSheet`) renders a `mapContent` detail on narrow screens; `MapPinPopup` is the anchored peek that expands into it.
- Non-`mapContent` details (settings, analytics, construct) are full-screen pushes on narrow.

## Centralized close affordance

One predicate fed by the allocator's fold state + push depth + breakpoint — never hardcoded per panel:

- **`X` (dismiss → reveals the map)**: always present on a panel/sheet root.
- **`←` (back one step)**: present **in addition** when something sits behind this panel — a push within it, a folded master, or a wizard step (list→hub). Wired to a *different* action than `X` (`←` = previous step/master; `X` = dismiss to map).

So a **root** shows **X only**; a **pushed step** shows **`←` + `X`** (confirmed by the Figma mobile sheets, frames 12752-39121 / 12752-40716).

## Route migration — delete, don't shim

- **Delete** the route-driven course/room tree from `routes.dart` (`/courses/:spaceid/{details,invite,analytics,addcourse,…}`, the shared `roomDetailsRoutes`, the `/courses` hub route, `_fullBleedRoute`/`_MainView` remnants).
- **Keep** `/rooms/:roomid` (upstream push / matrix.to deep links) and the UUID first-class world-object route.
- `legacy_redirects` rewrites every legacy inbound path → token URL (bookmarks / deep links only), idempotent.
- Course management → `course:<page>` pushes; room sub-pages (members/search/invite) → `room`-param pushes.

## Build order (no deferral)

1. **Registry schema + generalized `WorkspaceNav` API** + unit tests (pure).
2. **Centralized affordance predicate** (fold-aware) wired into both column hosts + the activity/map surfaces.
3. **Allocator**: expose `foldedOver` per slot; breakpoint → mobile mode signal.
4. **`MobileDetailSheet` + `MapPinPopup`** (generalize `MobileCourseSheet`); responsive detail rendering.
5. **Settings → master/detail + fold** (menu master + page detail; leaf pushes).
6. **Course-management + room sub-routes → token pushes**; **delete** the route-driven tree; redirects + tests.
7. **Match the mobile sheets to Figma** (peek heights, card chrome, pin popups; pull frames via the `figma` skill).
8. **Doc rewrite**: fold the durable model into `routing.instructions.md`; delete the temporary migration section and this file.

Each step ships green (analyze + nav tests) and is committed independently.
