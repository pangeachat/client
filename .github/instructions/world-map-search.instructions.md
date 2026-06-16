---
applyTo: "lib/routes/world/**,lib/features/quests/repo/**,lib/features/activity_sessions/**"
description: "World-map search + filter (Google-Maps UX) with personalized defaults — data sources, filter→query mapping, query boundary, and phasing."
---

# World Map — Search & Filter

Google-Maps-style search + filter on the **World** map. The map never serves the
whole library: the default view is a **personalized, viewport-bounded subset**,
and search/filters refine or widen from there. Cross-repo content model:
[courses-and-activities-v3](../../../.github/.github/instructions/courses-and-activities-v3.instructions.md).

## Default view = personalized, not the whole library

Before any search/filter, the World map shows: **my L2, at/below my CEFR, in the
current viewport, colored by my progress.** Derived only from signals that
already exist on `UserController` — no new capture:

- **L2** = `userController.userL2Code` → the bbox `l2` param (server-side equality). Null → omit (all languages) so the map is never empty.
- **CEFR band** = at-or-below `userController.userCefrLevel` (e.g. B1 → A1/A2/B1). v1 applies the band **client-side** over the result; null → no CEFR filter.
- **Viewport** = **deferred in v1.** The `/v2/activities/bbox` endpoint accepts the camera bounds but does **not** narrow by them yet (Payload can't range-filter the `coordinates` point field); it returns all *placed* activities matching L2/CEFR. The client still sends the camera bounds and re-fetches on pan/zoom so the wire contract is ready for real viewport narrowing — see [Query boundary](#query-boundary). At current catalog size, rendering every placed pin (clustered) is fine.
- **Progress** = unchanged pin coloring (`_userGoalTiers` gray/bronze/gold from Matrix state) — reflected, never filtered out.

The personalized default is the **initial filter state**, not a hard gate:
explicit filters and search refine it, and a one-tap **"reset to my defaults"**
returns to it. Empty-in-view shows a widen affordance (show all languages / zoom
out), so personalization never dead-ends.

## Filters → how each is satisfied

| Filter | Source | v1 |
| --- | --- | --- |
| **Target language (L2)** | choreo bbox `l2` param (CMS `res.plan.l2`, indexed) | **Re-fetch** on change (changes the working set; cheap + indexed) |
| **CEFR level** | `ActivityCard.cefr_level` on every card | **Client-filter** the band over the bounded result. Scale follow-up: widen the bbox `cefr_level` param to a comma list so the band bounds server-side (avoids the truncation hazard below) |
| **Per-activity completion** | Matrix room state, **not** the CMS | **Client-filter.** done = own role archived; in-progress = joined session, not archived; new = neither. Computed once into a Set, not per-frame per-room |
| **Theme / topic** | learning-objectives only (`res.theme`); **absent from the bbox card** | **Phase 2** — needs an LO-id join; add `objective_ids`/`theme` to the bbox endpoint (server-side join) |
| **Per-LO (Mission) completion** | client-derived: completed-activity-ids ∩ each LO's activities | **Phase 2** — needs `learningObjectiveRefs` in the working set (the bbox card drops them; add them to the card) |
| **Interests** | does not exist anywhere (client/choreo/CMS) | **Phase 3** — a captured structured `UserSettings.interests` aligned to CMS theme ids + onboarding/profile capture. Never proxied from free-text |

## Search = current-view, content match

v1 search filters the **already-loaded viewport pins** (no extra query) by
case-insensitive match over `title` + `description` + `learning_objective` (the
bbox card carries all three; the legacy client pin had only `title`). Debounced,
results-as-you-type, capped list; selecting a result flies to it via the existing
`MapFocus`/`_fitToContext` seam and opens the in-place preview. Off-screen
activities appear once panned into view (global text search is a later option).

## Query boundary

World pins route through the **existing choreographer `GET /v2/activities/bbox`**
(viewport + `l2` + `l1`), replacing `QuestRepo.mapActivities`' whole-library
500-row load. A thin `ActivityMapRepo.bboxPins({bounds, l2, l1, limit})` calls it
via `PApiUrls`/`Requests`. `CourseMapContext` stays on `QuestRepo.questPins`
(already quest-bounded). The client sends the camera bounds and debounces on
pan/zoom, capped by the endpoint `limit`. Routing through choreo (not a
client-direct CMS query) keeps a stable wire contract behind which the impl can
later add the PostGIS GiST `&&` viewport query with no client change.

**Viewport narrowing is deferred (FUTURE WORK).** The endpoint accepts the
bbox but uses it only as a "placed" gate today: it returns every placed
activity matching L2/CEFR, ignoring the box. Payload's `where` rejects range
filters on the `coordinates` point field's `.0`/`.1` sub-paths (400), and the
catalog is small enough that returning all placed pins is fine. Real viewport
narrowing needs a custom cms endpoint issuing
`ST_MakeEnvelope(min_lng,min_lat,max_lng,max_lat,4326) && coordinates` against
the GiST index on `res_plan_coordinates` (migration `20260614_134313`). The
choreo `discover_activity_cards` bbox branch and the
`/v2/activities/bbox` docstring carry the matching inline note. File the
density trigger in
[scaling-watchlist](../../../.github/.github/instructions/scaling-watchlist.instructions.md).

**Truncation:** with no viewport narrowing, the full placed-pin set (per L2)
is capped by `limit`; if it hits the cap, show a "more activities than shown"
signal rather than over-fetch — and note that v1's client-side CEFR band sits
*after* the server cap, so it can drop in-band pins. This is acceptable at
current catalog size; the server-side CEFR band (above) and viewport narrowing
(FUTURE WORK) both relieve it.
File the scale triggers in [scaling-watchlist](../../../.github/.github/instructions/scaling-watchlist.instructions.md).

## Clustering

`flutter_map_marker_cluster: ^8.2.2` (version-aligned with `flutter_map ^8.2.2`)
wraps the pin marker layer for the Google-Maps de-overlap feel. The preview
popup, `MapFocus` fly-to, and progress coloring are preserved.

## Phasing

- **v1:** personalized default (L2 + client CEFR band; **no** server-side viewport narrowing — all placed pins returned, clustered), current-view content search, filter chips (L2 re-fetch / CEFR band / completion), clustering, debounced pan-zoom re-fetch (contract-ready for viewport narrowing), reset-to-defaults + empty-state.
- **Phase 2:** theme + per-LO-completion filters (add `learningObjectiveRefs` + theme to the bbox card + an LO-id join param); server-side CEFR band; generalize the pin into a sealed `MapItem {kind, point, facets}` so locations join the same pipeline.
- **Phase 3:** captured `interests` feeding interest-based defaults; **PostGIS GiST viewport endpoint** behind the stable bbox contract when density triggers it (the deferred FUTURE WORK from [Query boundary](#query-boundary)); users-as-content (opt-in location).

## Key files

- Map + overlay: `lib/routes/world/world_map.dart` (wrap `FlutterMap` in a `Stack`; the search/filter overlay lives here to drive the in-state pin set + `_selectActivity`/`_fitToContext`).
- Pin fetch: `lib/features/quests/repo/activity_map_repo.dart` (new), `PApiUrls` bbox URL.
- Pin model: a content-search-capable card (title/description/learning_objective/cefr_level/l2/coordinates).
