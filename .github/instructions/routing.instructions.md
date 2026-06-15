---
applyTo: "lib/config/routes.dart,lib/features/navigation/**,lib/widgets/layouts/**,lib/widgets/space_navigation_column.dart,lib/widgets/navigation_rail.dart,lib/widgets/mobile_bottom_nav.dart"
description: "Client routing design guide — persistent-map shell, route_facts single source, canvas-once, one activity-open, and how to add a route."
---

# Client Routing

The world_v2 routing model in one page. For the visual layout contract (map
peeks, detail width, mobile sheet) see [layout.instructions.md](layout.instructions.md);
for cross-repo/external links see [deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md).

## The model

There is **one persistent `WorldMap`** for the whole app (a `GlobalKey` in
`TwoColumnLayout` keeps its State across navigation). Every section renders
*over* that map. A route's **canvas** ([CanvasMode]) says how:

- **mapHole** — paints nothing; the map shows through (section roots, column mode).
- **detail** — opaque panel capped at ~720px; the map peeks beside it.
- **fullBleed** — opaque content fills the canvas (the add-course hub).

The map is never remounted; sections do not own their own map.

## One source: `route_facts.dart`

Every routing/layout fact is derived in `lib/features/navigation/route_facts.dart`
— a module of small pure functions. The shell layout, the `routes.dart` page
builders, the left column, the rail, and the bottom nav all call these instead
of re-deriving from path segments, so they cannot disagree:

- `canvasFor(state, isColumnMode)` / `isMapHole(fullPath, isColumnMode)` — the canvas decision.
- `sectionFor(uri)` / `activeSpaceIdFor(uri)` — section + active course space.
- `activityFor(state)` / `mapFocusFor(state)` — the open activity and what the map focuses.
- `showLeftColumn(state)` / `showNavRail(state, isColumnMode)` — chrome visibility.

`sectionFor`/`activeSpaceIdFor`/`isMapHole` take primitives (`Uri`, `String`) so
they are unit-tested directly (`test/pangea/navigation/route_facts_test.dart`).
There is **no** `RouteContext` object, `PRouteId` enum, or parallel canvas Set —
the functions are the single definition.

### Resolution rules (the bugs this fixes)

- `activeSpaceIdFor` returns a space **only** for `/courses/!spaceid` (Matrix
  space ids start with `!`), so a `preview`/`own`/`browse` literal or a
  course-room id can never masquerade as the active space.
- A nested course room (`/courses/:spaceid/:roomid`) resolves to the **courses**
  section (not chats).
- Unknown routes resolve to `world` for the *nav highlight* only — the canvas is
  decided by `canvasFor`, never the section, so an unrecognized detail route
  never flips the shell to the map.

## Canvas declared once

Section-root page builders in `routes.dart` wrap their content in
`AppRoutes.canvasPage(context, state, content)`, which returns the map hole
(`EmptyPage`) or the content by calling `isMapHole`. The shell reads the same
`canvasFor`, so the page builder and the layout agree by construction. `/` is
always the map (both modes); the map-hole route set lives once in
`_mapHoleColumnRoutes` in route_facts.dart.

## Navigation: `PRoutes` only

Build world_v2 route strings with the `PRoutes` builders
(`PRoutes.course`, `PRoutes.activity`, `PRoutes.activityStandalone`, …) — never
hardcode `context.go('/courses/...')`. Fork-owned `/rooms/...` navigation is
left as upstream ships it (those routes are unchanged). `LegacyRedirects` is
**inbound-only**: it rewrites old/external shapes (incl. the retired nested
activity route) to canonical ones; no internal code emits legacy shapes.

## One activity-open mechanism

An activity opens as an in-place overlay over the persistent map
(`/courses/:spaceid?activity=:id`, optional `&roomid=` / `&launch=`), or via the
shareable standalone `/<uuid>` route — both build `ActivityDetailPanel`, the
sole route-path constructor of `ActivitySessionStartPage`. The old nested
`/courses/:spaceid/activity/:id` route is **deleted** (inbound-redirect only).
The non-route in-room mount (`chat_view` → `ActivitySessionStartPage`) is
unchanged.

## Map focus is extensible

`WorldMap` takes a `MapFocus?` (sealed). Today only `ActivityFocus` exists;
focusing new content (a location, a course region, a world object) is a new
`MapFocus` subclass plus one arm in `WorldMap._focusPoint` — the `switch` is
exhaustive, so the compiler flags the missing arm. Nothing else in routing
changes.

## How to add a route

1. Add the `GoRoute` in `routes.dart`. If it's a section root that should show
   the map in column mode, wrap its content in `canvasPage(...)` and add its
   `fullPath` to `_mapHoleColumnRoutes` in route_facts.dart.
2. Navigate to it via a `PRoutes` builder (add one if needed).
3. If `sectionFor`/`activeSpaceIdFor` need to recognize it, extend them and
   cover it in `route_facts_test.dart`.
4. If externally linkable, follow [deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md).
