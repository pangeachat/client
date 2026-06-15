---
applyTo: "lib/config/routes.dart,lib/config/p_route.dart,lib/features/navigation/**,lib/widgets/layouts/**,lib/widgets/space_navigation_column.dart,lib/widgets/navigation_rail.dart,lib/widgets/mobile_bottom_nav.dart"
description: "Client routing design guide — persistent-map shell, RouteContext, PLocation, canvas-per-route, and how to add a route."
---

# Client Routing

The world_v2 routing model in one page. For the visual layout contract (map
peeks, detail width, mobile sheet) see [layout.instructions.md](layout.instructions.md);
for cross-repo/external links see [deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md).

## The model

There is **one persistent `WorldMap`** for the whole app (a `GlobalKey` in
`TwoColumnLayout` keeps its State across navigation). Every section renders
*over* that map. A route's **canvas** says how:

- **map-hole** — paints nothing; the map shows through (section roots, in column mode).
- **detail** — opaque panel capped at ~720px; the map peeks beside it.
- **full-bleed** — opaque content fills the canvas (e.g. the add-course hub).

The map is never remounted; sections do not own their own map.

## One derivation: `RouteContext`

`RouteContext.fromState(state, isColumnMode)` is computed **once** at the shell
and threaded to everything (`TwoColumnLayout`, `SpaceNavigationColumn`/`_MainView`,
`SpacesNavigationRail`, `MobileBottomNav`, `WorldMap`). It is the single source
of: `section`, `activeSpaceId`, `activeRoomId`, `activeActivityId`
(+`activityRoomId`/`activityLaunch`), `canvasMode`, `isColumnMode`,
`showLeftColumn`/`showNavRail`/`showBottomNav`, `matchedRoute`.

**No widget re-derives these.** No `AppSection.fromUri`, no path-segment
parsing, no `state.fullPath` substring checks scattered across files. If two
places disagreed before (e.g. the rail highlighting a space the shell didn't),
that is what one derivation fixes.

## Identity & canvas come from the route, not the string

- Each world_v2/Pangea route has a **`PRouteId`**. Const maps key off it:
  `kRouteIdByPattern` (`state.fullPath` → id), `kSectionByRouteId`,
  `kCanvasByRoute`, `kCourseSpaceFamily`, `kHidesNavRail`.
- `activeSpaceId` is read **only** for routes in `kCourseSpaceFamily`, so a
  `preview`/`own`/`browse` literal or a course-room id can never masquerade as a
  space id (the bug positional `segments[1]` indexing caused).
- **Fork-owned detail leaves** (the shared `roomDetailsRoutes` mounted under
  rooms *and* courses, etc.) are intentionally **not** all enumerated. On a
  `kRouteIdByPattern` miss whose first segment is a known section, `RouteContext`
  resolves `canvasMode = detail` and `section` from that segment. Only a truly
  unrecognized path becomes `unknown` (debug assert + Sentry breadcrumb) — never
  a silent fall-through to the world map.

## Canvas declared once: `pRoute()`

Routes are built with `pRoute(path, id, canvas, content, hidesNavRail)` rather
than a raw `GoRoute`. The factory **derives the pageBuilder** from the single
`canvas` value (map-hole vs detail vs full-bleed), so the EmptyPage-vs-content
choice and the layout's mode can't drift. There is no separate `_mapCanvasPaths`
list to keep in sync. (`/` is always the map, in both column and narrow modes.)

## Navigation: `PLocation` only

`PLocation` (sealed) is the **only** way code builds a route string. One subclass
per destination; navigate with `PCourse(id).go(context)`, `PActivity(...).go(context)`,
etc. Never `context.go('/courses/$id')`. The fork-owned `/rooms/...` family are
`PLocation` subclasses too (they keep their existing string shape). The
`no_hardcoded_paths_test` guard fails the build on world_v2 path literals outside
`PLocation`/`routes.dart`. `LegacyRedirects` stays **inbound-only** (see the
deep-linking doc).

## How to add a route

1. In `routes.dart`, add `pRoute(path, id: PRouteId.x, canvas: CanvasMode.y, content: ...)`.
2. Add `PRouteId.x` and its entries to the const maps in `p_route_id.dart`
   (section, canvas, and `kCourseSpaceFamily`/`kHidesNavRail` if relevant).
3. Add a `PLocation` subclass and navigate through it.
4. Cover it in `route_context_test` (section/space/canvas resolution).
5. If externally linkable, follow [deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md).
