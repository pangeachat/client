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

## State — the panel is app-state, not a route

`AnalyticsPanelTab { vocab, grammar, sessions }` lives in `route_facts.dart`; the
open panel (tab + optional construct detail) lives in **`AnalyticsPanelController`**
— a `ValueNotifier<AnalyticsPanelState?>`, **deliberately not in the URL**.

- **Why not a query param.** A `?analytics=`/`?construct=` overlay is dropped by
  every left-side `context.go(...)` (nav rail, a chat, a course, a map pin) that
  doesn't carry it forward — so clicking anything on the left closed the panel.
  The panel is a *persistent personal companion* (interact with your stuff while
  you work), so it's app-state that navigation never touches. (The activity
  detail stays URL-routed — a focused task, fine to drop on nav.)
- The shell subscribes via `ValueListenableBuilder` on
  `AnalyticsPanelController.notifier`; the cluster opens it (`open(tab)`); the
  panel's close button calls `close()`. Trade-off: the panel is not
  URL-deep-linkable (fine for a transient overlay).
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
  `AnalyticsNavigationUtil.navigateToAnalytics`. When `AnalyticsPanelController.isOpen`
  it branches to the new system instead of the old `/rooms/analytics/...` pages:
  vocab/grammar call `openConstruct(tab, id)` (sets the tab + the selected
  `ConstructIdentifier` on the controller); an **activity opens its session
  chat** via `PRoutes.room` (the activity "detail" *is* a chat → left-zone
  content). Outside the panel (chat word-cards, banners) the old behavior is
  untouched.
- The panel renders the detail as `ConstructAnalyticsView(view: <tab's type>,
  construct: id, embedded: true)` (reuses `VocabDetailsView`/`MorphDetailsView`;
  the embedded flag also suppresses that view's internal close AppBar). The
  summary card is a second `ConstructAnalyticsView`/`ActivityArchive` with no
  construct.
- The detail card's header has a **back** arrow → `clearConstruct()` (return to
  summary); the summary's **close** → `close()` (whole panel). Switching trackers
  (`open(tab)`) clears any open construct so a leftover detail never renders under
  a mismatched tab.
- The right zone widens to two cards when a detail is open
  (`analyticsCardMax * 2 + gap`); a full-bleed panel shows one card and the
  detail's back returns to the summary.

## Shell layout — one budget, no overlap (`ShellLayout`)

The shell has a **single layout authority**: `ShellLayout.resolve(...)` (pure,
unit-tested — `shell_layout_test.dart`) computes one width budget that tiles
every floating zone over the persistent map so they **cannot overlap by
construction**. `TwoColumnLayout` reads it and places its `Positioned` children;
no zone computes its own width anymore. (The old bug: each zone — detail, panel —
sized itself independently and they collided; the detail didn't reserve the
panel's footprint.)

- Inputs: viewport, column/narrow, the left inset (rail + column), the canvas
  mode, and the open panel. Outputs: `leftInset`, `rightInset`, `detailWidth`
  (**bounded by both insets**, so the detail can't slide under the panel),
  `analyticsMode`, `clusterVisible`, and the map's left/right camera padding.
- **Tokens live in `ShellLayout`** (`detailMax` 720, `analyticsCardMax` 488,
  `clusterGutter` 88, `minCenter` 360) — the single source for these widths.
- **`AnalyticsPanelMode`** decides how the panel renders:
  - `dockedCard` — inset from the right by `clusterGutter`; the detail is bounded
    to its left and the vertical cluster sits in the gutter beside it (Figma
    `12731-427330`). Two cards when a construct detail is open.
  - `fullBleed` — a Slide-Over covering the content area, used on narrow screens
    **and** in column mode when there's no room to tile (an opaque center would
    drop below `minCenter`); the cluster hides.
  - `none` — closed, or suppressed on a full-bleed canvas (the add-course hub).
- Cluster: `Positioned(top:12+safe, right:12+safe)`, a vertical column (avatar
  over the trackers pill), shown only when `ShellLayout.clusterVisible`.

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

## Responsive (all resolved by `ShellLayout`, never overlapping)

- **Wide column**: zones tile — `[rail | left column | center/detail | analytics
  card | cluster gutter]`. The detail is bounded by the right inset; the vertical
  cluster sits in the gutter beside the card.
- **Tight column** (opaque center can't keep `minCenter` next to the panel, e.g.
  a course chat + panel below ~1350px): the panel becomes a **full-bleed
  Slide-Over** over the content; cluster hides. No overlap.
- **Narrow**: pages are full-width; the panel is a full-bleed Slide-Over; the
  cluster hides while it's open.

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
