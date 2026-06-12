---
applyTo: "lib/pangea/morphs/**, lib/pangea/constructs/**, lib/pangea/analytics_details_popup/morph_*"
---

# Grammar Analytics — Design & Intent

The grammar analytics section surfaces which morphological grammar concepts a learner has used (and which they haven't) based on the [Universal Dependencies](https://universaldependencies.org/) (UD) framework. In the UI it is labeled "Grammar" but internally the data model calls these **morph constructs** (`ConstructTypeEnum.morph`).

## Design Goals

### 1. Motivational progress tracker, not a textbook

The grammar page is **not** a grammar reference. It exists to let students see at a glance which grammar concepts they've already produced in real messages and which remain unused — promoting more varied, adventurous language use. The framing is "look what you've done / here's what you could try" rather than "here are 30 categories you need to learn."

### 2. Language-specific relevance

The full UD feature/tag inventory is large and language-agnostic. Only a subset manifests in any given L2. The server's `grammar-constructs` canonical CMS collection holds one row per target_language, audited end-to-end by an LLM panel to score 8. Each (feature, value) carries a `display: true|false` boolean that gates whether the pair surfaces in the analytics UI on a **manifestation test**: does this UD pair manifest in target_language as a dedicated form, productive periphrastic, or productive lexical pattern? Pedagogical placement (when on the CEFR curve) is the separate `sequence_position` field (1.0–6.0 float).

Cross-repo design: `pangeachat/.github/.github/instructions/grammar-constructs.instructions.md`.

> **Legacy fallback:** Before grammar-constructs v2 (shipped 2026-05-11), the server used an exclusion list (`morphs_exclusions_by_language.json` in 2-step-choreographer) plus a separate per-feature/tag morph_meaning collection for L1 strings. Those still exist transitionally during the client migration (see issue #6660) and will be deleted once the client fully consumes the new endpoints.

### 3. Tokenized dataset contribution

A secondary intent is to build up tokenized message datasets annotated with UD morphological information. This data helps improve NLP quality for low-resource languages where training data is scarce. Surfacing grammar analytics to users is partly a mechanism for generating and validating this annotation at scale.

## Data Architecture

### Construct model

Every grammar data point is a **construct** identified by a `ConstructIdentifier`:

| Field | Meaning | Example |
|---|---|---|
| `type` | Always `ConstructTypeEnum.morph` | `morph` |
| `category` | The UD feature name (maps to `MorphFeaturesEnum`) | `Tense` |
| `lemma` | The UD tag value within that feature | `Pres` |

A user's usage of each construct is tracked as `ConstructUses`, which accumulates XP and a proficiency level (`ConstructLevelEnum`).

### Morph feature inventory

Source of truth for the per-language inventory is the `grammar-constructs` CMS collection: one row per target_language, holding the audited (feature, value) bundle with `display`, `sequence_position`, and a worked `example` per value. The client fetches via `POST /choreo/grammar_constructs/canonical` (single canonical inventory) or `POST /choreo/grammar_constructs` (joined: canonical + L1 strings in one call — the recommended consumer surface). Sort order is driven by `sequence_position` on each value; the legacy `morphFeatureSortOrder` constant is superseded.

The client retains a `defaultMorphMapping` fallback (`default_morph_mapping.dart`) for offline / unauthenticated cases.

### Human-readable descriptions

L1-language titles and descriptions come from the server, not from client-side localization. Each canonical row pairs with per-`(feature, target_language, user_l1)` translation rows in `grammar-construct-meanings`. The joined endpoint returns:

- `feature_title` in user_l1 (e.g. "시제" for Tense when user_l1=ko)
- per-value `title` in user_l1 (e.g. "현재 시제" for Pres)
- per-value `description` in user_l1 (2–3 sentence pedagogical explanation)

Cache-miss translation rows are generated on demand via the panel-eval cascade (canonical doc score gates publication at ≥ 8; translation score gates per-L1 visibility independently — low-score Korean falls back to source_l1 text). The legacy `get_grammar_copy.dart` hardcoded copy and matching `grammarCopy*` L10n keys are obsolete under the new model and slated for removal (Phase 3 of #6660).

## UI Structure

### Grammar list view (`morph_analytics_list_view.dart`)

Top-level page showing all relevant UD features as expandable boxes. Each box lists the tags within that feature (e.g., Tense → Past, Present, Future). Tags are color-coded by the user's proficiency level. Tags the user hasn't encountered yet are visible but dimmed — this is intentional to motivate exploration.

### Grammar detail view (`morph_details_view.dart`)

Drill-down for a single tag showing:
- Tag display name and icon (`morph_tag_display.dart`, `morph_icon.dart`)
- Feature category label (`morph_feature_display.dart`)
- Human-readable meaning (`morph_meaning_widget.dart`)
- XP progress bar
- Usage examples from the user's actual messages

### Grammar practice (`grammar_error_practice_generator.dart`, `morph_category_activity_generator.dart`)

Recent addition: users can practice grammar concepts they've struggled with. `GrammarErrorPracticeGenerator` creates activities from past writing-assistance grammar corrections. `MorphCategoryActivityGenerator` creates practice targeting specific morph categories.

## Recent Improvements

- **Grammar practice section** on the analytics page allowing rehearsal of past grammar mistakes via generated multiple-choice activities.

## Future Work

- **Client migration onto grammar-constructs v2** (#6660): replace `morph_repo.dart` + `morph_info_repo.dart` with a single `grammar_constructs_repo.dart` backed by `POST /choreo/grammar_constructs`. Phased plan in the issue body.
- **In-app feedback on grammar info**: Allow users to flag incorrect or confusing tags/descriptions to trigger an audit pass on the (feature, target_language) canonical or the (feature, target_language, user_l1) translation row. The handler already supports feedback-driven regeneration via the existing `LLMBaseHandler` feedback channel.
- **Target grammar in activities**: Allow course creators and activity generators to specify grammar concepts as learning targets (e.g., "practice the subjunctive"), connecting the grammar inventory to the activity system. The new `sequence_position` makes "next concept on the CEFR curve" a queryable property.

## Key Files

| Area | Files |
|---|---|
| **Data model** | `constructs/construct_identifier.dart`, `analytics_misc/construct_type_enum.dart`, `analytics_misc/construct_use_model.dart` |
| **UD features** | `morphs/morph_features_enum.dart`, `morphs/morph_models.dart`, `morphs/default_morph_mapping.dart`, `morphs/parts_of_speech_enum.dart` |
| **Display copy** | Server-driven via the joined endpoint. Legacy `morphs/get_grammar_copy.dart` + `morphs/morph_meaning/` slated for removal in #6660 Phase 3. |
| **API** | `morphs/morph_repo.dart` + `morph_meaning/morph_info_repo.dart` (legacy, transitional). New consumer surface is `POST /choreo/grammar_constructs` (joined). |
| **UI — list** | `analytics_details_popup/morph_analytics_list_view.dart`, `analytics_details_popup/analytics_details_popup.dart` |
| **UI — detail** | `analytics_details_popup/morph_details_view.dart`, `morphs/morph_tag_display.dart`, `morphs/morph_feature_display.dart`, `morphs/morph_icon.dart` |
| **Practice** | `analytics_practice/grammar_error_practice_generator.dart`, `analytics_practice/morph_category_activity_generator.dart` |
| **Server — canonical (new)** | `2-step-choreographer: app/handlers/grammar_constructs/canonical_handler.py`; CMS `grammar-constructs` collection |
| **Server — translations (new)** | `2-step-choreographer: app/handlers/grammar_constructs/meaning_handler.py`; CMS `grammar-construct-meanings` collection (one row per (feature, target_language, user_l1)) |
| **Server — legacy (transitional)** | `2-step-choreographer: app/handlers/universal_dependencies/` (tag lists), `app/handlers/morph_meaning/` (descriptions). Both slated for deletion in #6660 Phase 4. |
