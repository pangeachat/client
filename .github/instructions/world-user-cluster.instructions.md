---
applyTo: "lib/routes/world/**,lib/widgets/layouts/two_column_layout.dart,lib/features/navigation/**"
description: "World-map top-right user cluster (leveled avatar + XP ring + vocab/grammar/sessions trackers) and the right-docked analytics overlay it opens."
---

# World — Top-Right User Cluster + Right-Docked Analytics

A persistent **top-right cluster** over the world map (Figma "Avatar with level"):
the user's avatar wrapped in a circular **XP ring**, a gold **level badge**, the
L2 **flag**, and a vertical pill of three tappable **trackers** — completed
**Sessions** (top), **Grammar** (middle), **Vocabulary** (bottom). Tapping a
tracker opens that metric's analytics **docked on the right** over the map; the
cluster stays pinned on top. Companion: [routing.instructions.md](routing.instructions.md),
[analytics-system.instructions.md](analytics-system.instructions.md).

> Stars are now map pins / goal progress, **not** level. Level is the gold badge.

## Two surfaces

1. **`WorldUserCluster`** (`lib/routes/world/world_user_cluster.dart`) — a pinned
   top-right overlay, mounted as a sibling of the persistent map in the shell so
   it survives section navigation (never remounts). Composition:
   - **Leveled avatar**: `Avatar` (own profile) + a `CustomPaint` XP ring
     (`levelProgress` 0..1, gold) + a gold level-badge ("N") bottom-center + the
     L2 flag.
   - **Trackers pill**: a white rounded pill, three `GestureDetector` rows
     top→bottom — Sessions / Grammar / Vocabulary — each an icon + count.
2. **`WorldAnalyticsPanel`** (`lib/routes/world/world_analytics_panel.dart`) — a
   right-docked overlay driven by the `?analytics=<tab>` query param (mirrors the
   `?activity=` pattern). Hosts the **existing** analytics widgets unchanged:
   - `vocab` → `ConstructAnalyticsView(view: ConstructTypeEnum.vocab)`
   - `grammar` → `ConstructAnalyticsView(view: ConstructTypeEnum.morph)`
   - `sessions` → `ActivityArchive()`

## Data sources (all already client-side; no new fetch)

Access via `Matrix.of(context).analyticsDataService` (`MatrixState.analyticsDataService`),
language = `userController.userL2` (`langCodeShort`). Gate on `initCompleter`.

| Datum | Source | Reactivity |
| --- | --- | --- |
| **Level** (badge) | `(await derivedData(l2)).level` | `constructUpdateStream` |
| **XP fraction** (ring) | `(await derivedData(l2)).levelProgress` (0..1) | `constructUpdateStream` |
| **Vocab #** | `numConstructs(ConstructTypeEnum.vocab)` (sync, in-memory) | `constructUpdateStream` |
| **Grammar #** | `numConstructs(ConstructTypeEnum.morph)` (sync) | `constructUpdateStream` |
| **Sessions #** | `client.ownAnalyticsRoomLocalByL2?.archivedActivities.length ?? 0` | `activityAnalyticsStream` |
| **Avatar** | `client.fetchOwnProfile()` → `avatarUrl` + displayname | — |
| **L2 flag** | `userController.userL2` (flag emoji / `langCodeShort`) | language change |

`numConstructs` reads the in-memory merge table (respects blocked constructs).
Use `derivedData` (local, from totalXP) for level — **not** the public-profile
`AnalyticsProfileModel.level`, which can lag. The Sessions count must match what
the `sessions` panel shows (both `archivedActivities`).

## Routing — `?analytics=<tab>` overlay

`AnalyticsPanelTab { vocab, grammar, sessions }` lives in `route_facts.dart`.

- `analyticsFor(GoRouterState)` → `AnalyticsPanelTab?` from `?analytics=`.
- Opening preserves the underlying route: `context.go(uri + {analytics: tab})`.
  Closing drops only `analytics` (mirrors `ActivityDetailPanel._close`).
- **Independent overlay, not a `canvasFor` change.** The activity detail is
  *left-anchored* (after the column); the Figma analytics card is *right-anchored*
  over the map. So the panel is a separate right-docked `Positioned` child in the
  shell — it does not consume the canvas slot. This is lower-risk than reworking
  `canvasFor`, and it coexists with the map-hole world view (the common case).
- The cluster trackers are now the **primary** analytics entry point. The old
  left-column **analytics nav-rail button is removed** (`navigation_rail.dart`).
  The `/analytics/*` section routes still exist (deep-links + the mobile bottom
  nav), but to avoid the old left-column presentation appearing inside the new
  panel, the hosted views (`ConstructAnalyticsView`, `ActivityArchive`) take an
  `embedded` flag that **hides the cross-metric `LearningProgressIndicators`
  header** (its tabs navigate to the section routes). Metric switching is the
  cluster's job. The panel passes `embedded: true`.
- `WorldMap` gains `rightOverlayWidth` (parallel to `leftOverlayWidth`) so a
  course camera-fit pads for the right panel; the right fit padding becomes
  `rightOverlayWidth + 64`.

## Drilling in — detail card LEFT of the pinned summary

Clicking a vocab word or grammar concept opens its **detail as a card to the
LEFT of the summary**; the summary never moves (Figma `12722-158370`). This is
the RTL "personal stuff" pattern: the anchor (cluster + summary) is on the right,
so detail blooms left into the open canvas. No deeper drill (one detail level).

- **One chokepoint.** All three item clicks funnel through
  `AnalyticsNavigationUtil.navigateToAnalytics`. When `?analytics=` is present
  (we're in the panel) it branches to the new system instead of the old
  `/rooms/analytics/...` pages: vocab/grammar add `?construct=<json>` (the
  selected `ConstructIdentifier`); an **activity opens its session chat** via
  `PRoutes.room` (the activity "detail" *is* a chat → left-zone content).
  Outside the panel (chat word-cards, banners) the old behavior is untouched.
- `analyticsConstructFor(state)` decodes `?construct=`. The panel renders the
  detail as `ConstructAnalyticsView(view: <tab's type>, construct: id,
  embedded: true)` (reuses `VocabDetailsView`/`MorphDetailsView`; the embedded
  flag also suppresses that view's internal close AppBar). The summary card is a
  second `ConstructAnalyticsView`/`ActivityArchive` with no construct.
- The detail card's header has a **back** arrow that drops only `?construct`
  (return to summary); the summary's **close** drops `?analytics` (+`construct`).
- Switching trackers (`WorldUserCluster._openAnalytics`) drops `?construct` so a
  leftover detail never renders under a mismatched tab.
- The right zone widens to two cards when a detail is open
  (`_analyticsPanelMaxWidth * 2 + gap`); narrow mode shows one card and the
  detail's back returns to the summary.

## Shell mounting (`two_column_layout.dart`)

Add two `Positioned` children **after** `SpaceNavigationColumn` (z-order on top
of the map): `… , WorldAnalyticsPanel (when open), WorldUserCluster`.

- Cluster: `Positioned(top: 12 + safeTop, right: 12 + safeRight)`, a **vertical**
  column (avatar over a vertical trackers pill). Hidden on a `fullBleed` canvas,
  and (narrow mode) while the panel is open.
- Panel (column mode): a right-docked card **inset from the right edge by
  `_clusterGutter` (~88px)** so the vertical cluster sits in that gutter *beside*
  the panel — over the map — instead of covering the page (Figma `12731-427330`:
  the cards leave a right gutter for the cluster; the map shows below it). Card
  `width = min(488, available − gutter)`; the zone holds two cards when a detail
  is open. Narrow mode → full-bleed page (`right: 0`), cluster hidden.

## Theming

`AppConfig.gold` (#FDBF01) ring + badge; `AppConfig.goldLight` ring track;
`AppConfig.borderRadius` (18) / smaller radius on the pill; `FluffyThemes`
`animationDuration`/`animationCurve`; `Theme.of(context).colorScheme.surface`
panel bg. Icons (`material_symbols_icons`): `Symbols.dictionary` (vocab),
`Symbols.toys_and_games` (grammar), a sessions icon (e.g. `Symbols.fitness_center`
/ activity icon). Match `LearningProgressIndicators` if it already maps these.

## l10n (template `lib/l10n/intl_en.arb`; run `flutter gen-l10n`)

`worldTrackerSessions`, `worldTrackerGrammar`, `worldTrackerVocab`,
`worldLevelBadge` ({level}), and reuse existing `close`/analytics titles where
present. Never hardcode UI strings.

## Responsive

- **Column** (`FluffyThemes.isColumnMode`): the vertical cluster sits in the
  right gutter; the panel (one card, or detail + summary) docks to its left.
  Both visible together (verified at 1568px and ~977px).
- **Narrow**: pages are **full-width** and the cluster is hidden while a page is
  open, so the vertical cluster never overlaps a full-width page.

## Testing

- `flutter analyze` clean; `flutter gen-l10n` before analyze.
- Browser (web-server :8090): cluster renders over the map with live counts;
  level badge + ring reflect `derivedData`; tap each tracker → correct right
  panel; close returns to the map; avatar tap → `/profile`. Verify desktop
  (≥1334px) and a narrow viewport. Confirm counts match the opened panel.

## Follow-ups (not in v1)

- The `/analytics/*` section routes still exist for deep-links + the mobile
  bottom nav (which still has an analytics button). Decide whether to also route
  those through the right-docked overlay, or retire them once the cluster is the
  sole entry point everywhere.
- Avoid the residual double-state where a section route (`/analytics/morph`) and
  the `?analytics=` overlay can both be in the URL at once (only reachable now by
  hand-crafted/legacy links, since the in-panel tabs are hidden).
- Figma "search + download" affordances on the vocab card header.
- Animate the ring / panel slide-in; level-up flourish on the badge.
