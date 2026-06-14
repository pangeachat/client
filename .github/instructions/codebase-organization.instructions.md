---
description: "Codebase organization map for the Flutter client — the routes/features/pangea split over the FluffyChat base, and where new code goes (Placement Decision Tree)."
applyTo: "lib/routes/**,lib/features/**,lib/pangea/**,lib/main.dart,lib/config/routes.dart"
---

# Codebase Organization

This client is a fork of [krille-chan/fluffychat](https://github.com/krille-chan/fluffychat). Pangea code was reorganized on top of that base into three trees: **`lib/routes/`** (on-screen UI, by nav section), **`lib/features/`** (per-domain data and logic), and **`lib/pangea/`** (shared infra and common widgets). FluffyChat base layers (`lib/widgets/`, `lib/utils/`, `lib/config/`) remain underneath, edited in place. This doc is the map: read it, then use the Placement Decision Tree to decide where new code goes. For the feature-module map inside `lib/pangea/`, see [modules.instructions.md](modules.instructions.md) (not repeated here).

## Top-Level Directories

| Dir | Role | Examples |
| --- | --- | --- |
| `lib/routes/` | Pages and on-screen UI, organized by nav section (GoRouter destinations). Screens, views, controllers, and route-local widgets live here. `chat/` also houses `choreographer/` and `events/`. | [`routes/courses/find_course_page.dart`](../../lib/routes/courses/find_course_page.dart), [`routes/world/activity_map_page.dart`](../../lib/routes/world/activity_map_page.dart), [`routes/chat/events/constants/pangea_event_types.dart`](../../lib/routes/chat/events/constants/pangea_event_types.dart) |
| `lib/features/` | Per-domain data and logic: models, repos, Matrix Room/Client `*_extension.dart`, services, constants, enums. Mostly data, with a few in-domain UI primitives (see split rule). | [`features/course_plans/courses/course_plans_repo.dart`](../../lib/features/course_plans/courses/course_plans_repo.dart), [`features/languages/language_repo.dart`](../../lib/features/languages/language_repo.dart), [`features/navigation/route_paths.dart`](../../lib/features/navigation/route_paths.dart) |
| `lib/pangea/` | Shared Pangea infra and common widgets used across features: network layer, `PangeaController`, common widgets, cross-cutting Matrix extensions, plus a few shared-infra domains (lemmas, morphs). | [`pangea/common/network/urls.dart`](../../lib/pangea/common/network/urls.dart), [`pangea/common/controllers/pangea_controller.dart`](../../lib/pangea/common/controllers/pangea_controller.dart), [`pangea/extensions/pangea_room_extension.dart`](../../lib/pangea/extensions/pangea_room_extension.dart) |
| `lib/widgets/` | FluffyChat base plus general app chrome not tied to one route: root state, nav rail, mobile bottom nav, avatar, dialogs, layouts. Many carry `// #Pangea` edits. | [`widgets/matrix.dart`](../../lib/widgets/matrix.dart) (`MatrixState` root state), [`widgets/navigation_rail.dart`](../../lib/widgets/navigation_rail.dart), [`widgets/avatar.dart`](../../lib/widgets/avatar.dart) |
| `lib/utils/` | FluffyChat base cross-app helpers: client manager, http client, file/share/push helpers, base extensions. Edit in place with `// #Pangea` fences. | [`utils/client_manager.dart`](../../lib/utils/client_manager.dart), [`utils/custom_http_client.dart`](../../lib/utils/custom_http_client.dart) |
| `lib/config/` | App configuration (FluffyChat base): the GoRouter table, themes, app config, setting keys. | [`config/routes.dart`](../../lib/config/routes.dart), [`config/themes.dart`](../../lib/config/themes.dart), [`config/app_config.dart`](../../lib/config/app_config.dart) |

## The features ↔ routes Split

The dominant pattern: domain **data/logic** goes in `lib/features/<domain>/`; on-screen **UI** goes in `lib/routes/<nav_section>/`. Course plans illustrate it: data in [`features/course_plans/courses/`](../../lib/features/course_plans/courses/) (repo, model, room extension), screens in [`routes/courses/`](../../lib/routes/courses/) (`find_course_page.dart`, `add_course_hub_view.dart`).

The rule is real but imperfectly enforced. A few feature dirs hold UI today (`features/subscription/widgets/`, `features/bot/widgets/`, `features/tutorials/*_widget.dart`). Keep new **full-screen pages** in `lib/routes/`. A widget may stay in a feature dir only if it is a small in-domain primitive reused across multiple routes; anything that is a screen belongs in `lib/routes/` so the nav taxonomy stays the place to find UI.

## Imports and the `// #Pangea` Marker

- **Package prefix is `fluffychat`, not `client`** (inherited from the fork). All intra-app imports use `package:fluffychat/...`, e.g. `package:fluffychat/routes/...`, `package:fluffychat/features/...`, `package:fluffychat/pangea/common/config/environment.dart`.
- **Edits to base FluffyChat files are fenced in `// #Pangea` ... `// Pangea#`** so they survive upstream merges and stay greppable (~100 files carry the fence). Use it when modifying a base file in `lib/widgets/`, `lib/utils/`, `lib/config/`, etc. Net-new Pangea code lives in its own file under `pangea/`, `features/`, or `routes/` and does not need the fence.

## Placement Decision Tree

Most important section. Pick the first matching case.

| You are adding... | Goes in | Example |
| --- | --- | --- |
| Full-screen page / view (a GoRouter destination) | `lib/routes/<nav_section>/`, named `*_page.dart` or `*_view.dart` | [`routes/courses/find_course_page.dart`](../../lib/routes/courses/find_course_page.dart) |
| Widget used only inside one screen | `lib/routes/<nav_section>/` beside the page, named `*_widget.dart` | [`routes/chat/activity_sessions/activity_summary_widget.dart`](../../lib/routes/chat/activity_sessions/activity_summary_widget.dart) |
| API call + its request/response models (feature data layer) | `lib/features/<domain>/`, flat as `<domain>_repo.dart` (split into subdomain dirs, or a `repo/` sub-dir, once a domain grows multiple repos) | [`features/course_plans/courses/course_plans_repo.dart`](../../lib/features/course_plans/courses/course_plans_repo.dart) |
| API call for a `pangea/` shared-infra domain (lemmas, morphs) | `lib/pangea/<domain>/`, flat as `<name>_repo.dart` | [`pangea/lemmas/lemma_info_repo.dart`](../../lib/pangea/lemmas/lemma_info_repo.dart), [`pangea/morphs/grammar_constructs_repo.dart`](../../lib/pangea/morphs/grammar_constructs_repo.dart) |
| Domain model / enum / feature-scoped logic (no UI) | `lib/features/<domain>/` | [`features/activity_sessions/activity_plan_model.dart`](../../lib/features/activity_sessions/activity_plan_model.dart) |
| Cross-cutting Matrix Room/Client extension (app-wide) | `lib/pangea/extensions/` | [`pangea/extensions/pangea_room_extension.dart`](../../lib/pangea/extensions/pangea_room_extension.dart) |
| Reusable Pangea-branded/feature widget (2+ places) | `lib/pangea/common/widgets/` | [`pangea/common/widgets/pressable_button.dart`](../../lib/pangea/common/widgets/pressable_button.dart) |
| Reusable app-chrome widget (nav, avatar, dialog, layout) | `lib/widgets/` (FluffyChat base) | [`widgets/navigation_rail.dart`](../../lib/widgets/navigation_rail.dart) |
| Network base (urls, http) or app-wide controller | `lib/pangea/common/network/`, `lib/pangea/common/controllers/` | [`pangea/common/network/urls.dart`](../../lib/pangea/common/network/urls.dart) |
| Generic cross-app helper, or edit to a base helper | `lib/utils/` (fence base-file edits with `// #Pangea`) | [`utils/custom_http_client.dart`](../../lib/utils/custom_http_client.dart) |
| Pangea-only helper shared across features | `lib/pangea/common/utils/` | [`pangea/common/utils/`](../../lib/pangea/common/utils/) |
| Helper used by exactly one domain | that feature's dir | [`features/languages/language_service.dart`](../../lib/features/languages/language_service.dart) |
| Route-path constant / nav taxonomy | `lib/features/navigation/route_paths.dart` (`PRoutes`) | [`features/navigation/route_paths.dart`](../../lib/features/navigation/route_paths.dart) |

Shared-widget tie-breaker: a reusable Pangea-branded widget could plausibly land in `lib/widgets/` or `lib/pangea/common/widgets/`. Put shared Pangea-branded widgets in `lib/pangea/common/widgets/` and reserve `lib/widgets/` strictly for FluffyChat-base app chrome.

## Known Cruft (Being Cleaned Up)

- **`lib/pages_v2/`** is a stale empty scaffold (zero `.dart` files). New pages go in `lib/routes/`, not here.
- **`lib/pangea/design_system/`** (and `tokens/`) hold no source. The "design tokens" home is not real code yet; do not route shared widgets there.
- **`copilot-instructions.md` Project Structure is stale**: it references `lib/pages/` (now `lib/routes/`), calls `lib/pangea/` "all Pangea code" (logic is now split into `lib/features/`), and lists `pangea_event_types.dart` / `choreographer.dart` under `lib/pangea/` though both moved to `lib/routes/chat/`. Trust this doc and the tree, not those lines.

## Future Work

_(No linked issues yet.)_
