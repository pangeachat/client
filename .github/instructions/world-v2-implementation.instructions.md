---
description: "World v2 client implementation plan — nav re-root, Avatar merge, add-course popover, course learning-objective sections, mobile bottom nav."
applyTo: "lib/features/navigation/**,lib/widgets/navigation_rail.dart,lib/widgets/space_navigation_column.dart,lib/config/routes.dart,lib/routes/world/**,lib/routes/courses/**"
---

# World v2 — Client Implementation

Stable design: the org repo's `vision/world_v2.md`. This doc is the tactical build plan for the world-screens pass on top of PR [#6980](https://github.com/pangeachat/client/pull/6980) (branch `feat/world-v2-map-canvas`). Branch: `feat/world-v2-nav-and-course-lo`.

The map is the canvas the app sits on; every section is an overlay over it. Nav model: **World · Chats · Analytics · Avatar · Add-course**, plus a selected-space switcher slot. Rail (wide) top→bottom: Avatar · space-switcher · Chats · Analytics · World · Add(+). Mobile: bottom nav with the same slots.

## Decisions in effect (resolved with Will)

- **Learning objectives are the course's organizing unit** (replacing topics). This pass adds a **thin link** only: an `objective` relationship on `course-plan-activities` → `learning-objectives`, backfilled from the seed's provenance. No course-plan sequence restructure.
- **Course left column = location-grouped LO sections.** City labels are **derived from activity map data** (coordinates → existing location name, reverse-geocode only when missing), NOT a topic record. LOs are the unlockable items inside each location group.
- **`/` = World** (map root, column and narrow); **Chats moves to `/chats`**. `/rooms/:roomid` stays (push/matrix.to); bare `/rooms` → redirect `/chats`.
- **Avatar = profile + settings merged** into one rail slot and one surface; `/profile` renders profile header + settings menu; `/settings/*` detail routes stay.
- **Add-course = popover menu** off the rail `+`: Start my own (`/courses/own`), Enter code (`/courses/private`), Browse public (`/courses`).
- **Mobile bottom nav + space-switcher sheet** are in scope this pass.

## Default sub-decisions

- World's left column is map-only for now; filters are a later slice.
- Avatar reuses existing `Settings()` content under a profile header, not a rewrite.
- City labels prefer existing `course-plan-*-location` names; reverse-geocode only when absent.

## Streams (dependency order)

1. **Nav skeleton** — `AppSection` (add `world`; `chats`→`/chats`; one Avatar slot for profile|settings), `route_paths.dart` (`chats='/chats'`), `routes.dart` (`/chats`, `/`=World, `/rooms`→`/chats`), `legacy_redirects.dart` + tests, `navigation_rail.dart` reorder, `space_navigation_column.dart` `_MainView` cases.
2. **Add-course popover** off the rail `+`.
3. **Avatar surface** (profile header + settings menu).
4. **CMS thin link + backfill** — cms `objective` relationship field + migration; choreo `backfill_activity_objectives.py` (reverse seed `source_activity_ids`). Run local.
5. **Course view** — location-grouped LO sections from activities' `objective` + coordinates; activity pins on map.
6. **Mobile bottom nav + space switcher sheet.**
7. **Tests + live verify** — `app_section_test`, `legacy_redirects_test`, `flutter analyze`, Chrome against local stack (learner/learnerpass).

## Source-tree note (post-reorg)

Gabby's reorg moved `lib/pangea/**` feature modules → `lib/features/**` and route-specific pages → `lib/routes/**`. Navigation lives in `lib/features/navigation/`; world pages in `lib/routes/world/`. Imports are `package:fluffychat/features/...` and `package:fluffychat/routes/...`.
