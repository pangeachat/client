---
applyTo: "lib/features/languages/**,lib/routes/settings/settings_learning/**"
---

# Language List — Client

For the cross-service language list architecture, L1/L2 definitions, and CMS schema, see [language-list.instructions.md](../../../.github/.github/instructions/language-list.instructions.md).

## Data Flow

1. [`LanguageRepo._fetch()`](../../lib/features/languages/language_repo.dart) fetches all languages from CMS REST API (`/api/languages?limit=500&sort=language_name`) — public, no auth
2. [`PLanguageStore`](../../lib/features/languages/p_language_store.dart) caches the list in `SharedPreferences` and re-fetches roughly daily
3. Hardcoded fallback in [`LanguageConstants.languageList`](../../lib/features/languages/language_constants.dart) if CMS is unreachable and cache is empty

## L1/L2 Filtering

[`PLanguageStore`](../../lib/features/languages/p_language_store.dart) exposes three getters:

| Getter | Filter | Used for |
|---|---|---|
| `baseOptions` | All languages minus same-script **regional** variants — English (US/UK), Spanish (Mexico), etc. are dropped; a genuinely different **writing system** (Traditional Chinese, Jawi Malay, Shahmukhi Punjabi) is kept | L1 / source / native language selection |
| `targetOptions` | `element.l2` (i.e., `l2Support != L2SupportEnum.na`) | L2 / target / learning language selection |
| `unlocalizedTargetOptions` | L2 filter + excludes regional variants (e.g., keeps "Portuguese" but not "Portuguese (Brazil)") | Course creation language filter |

The `l2` getter on [`LanguageModel`](../../lib/features/languages/language_model.dart) returns `l2Support != L2SupportEnum.na`.

## Key Usage Sites

- **Learning settings dialog**: [`p_language_dialog.dart`](../../lib/routes/settings/settings_learning/p_language_dialog.dart) — `baseOptions` for L1, `targetOptions` for L2
- **Learning settings view**: [`settings_learning_view.dart`](../../lib/routes/settings/settings_learning/settings_learning_view.dart) — same pattern
- **Bot chat settings**: [`bot_chat_settings_dialog.dart`](../../lib/features/bot/widgets/bot_chat_settings_dialog.dart) — `targetOptions` for room target language
- **Course creation**: [`course_language_filter.dart`](../../lib/routes/courses/course_language_filter.dart) — `unlocalizedTargetOptions`
- **Login language selection**: the old `language_selection_page.dart` no longer exists; where login language selection now lives needs a doc pass against the current login flow

## Models

- [`LanguageModel`](../../lib/features/languages/language_model.dart) — core model with `langCode`, `displayName`, `l2Support`, `script`, `localeEmoji`, and labeled voice options
- [`L2SupportEnum`](../../lib/features/languages/l2_support_enum.dart) — `na`, `alpha`, `beta`, `full` with localized display strings and badge rendering
- [`LanguageArc`](../../lib/features/languages/language_arc_model.dart) — L1→L2 pair, constructed from user settings

## Conventions

- Display names are localized via `getDisplayName(context)` using l10n keys, with fallback to CMS `language_name`
- The CMS `voices` field is hydrated as voice option objects with `short_name` + `display_name`; `LanguageModel.voices` remains a convenience getter that exposes only short names for persisted settings
- Client hydration must remain backward-compatible with legacy `voices: list[str]` CMS responses until choreographer re-syncs every language row
- Regional variants show `localeEmoji` in place of parenthesized region: "Portuguese 🇧🇷" instead of "Portuguese (Brazil)"
- `langCodeShort` strips the territory: `en-US` → `en`
- RTL detection uses a hardcoded list in `LanguageConstants.rtlLanguageCodes`

## Future Work

_(No linked issues yet.)_
