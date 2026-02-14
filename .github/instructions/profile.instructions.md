---
applyTo: "lib/pangea/user/user_model.dart, lib/pangea/user/user_controller.dart, lib/pangea/user/public_profile_model.dart, lib/pangea/user/analytics_profile_model.dart, lib/pangea/chat_settings/utils/bot_client_extension.dart, lib/pangea/chat_settings/models/bot_options_model.dart, lib/pangea/bot/utils/bot_room_extension.dart, lib/pangea/bot/widgets/bot_chat_settings_dialog.dart, lib/pangea/learning_settings/**, lib/pangea/common/controllers/pangea_controller.dart"
---

# Profile Settings — Architecture & Contracts

How profile settings are structured, stored, propagated, and surfaced to other users.

## Data Model

`Profile` (in [user_model.dart](lib/pangea/user/user_model.dart)) is the top-level container. It wraps three sub-models:

- **`UserSettings`** — learning prefs: target/source language, CEFR level, gender, voice, country, about, etc.
- **`UserToolSettings`** — per-tool on/off toggles (interactive translator, grammar, immersion mode, definitions, auto-IGC, autocorrect, TTS).
- **`InstructionSettings`** — which instructional tooltips the user has dismissed.

A separate **`PublicProfileModel`** (in [public_profile_model.dart](lib/pangea/user/public_profile_model.dart)) holds data visible to other users: analytics level/XP per language, country, and about. It lives on the Matrix user profile (public), not in account data.

> **Open question**: `country` and `about` are the only fields that cross the private → public boundary (they live in `UserSettings` but get synced to `PublicProfileModel`). It might be cleaner to keep them solely in `PublicProfileModel` and edit them in a "public profile" editor, making the privacy boundary explicit.

## Storage & Sync

| Concern | Design Decision | Why |
|---|---|---|
| **Format** | Single JSON blob in Matrix account data under key `profile` | Atomic writes; no partial-update races between fields |
| **Cross-device sync** | Rides on standard Matrix sync | No extra infrastructure; every logged-in device gets updates automatically |
| **Caching** | `UserController` reads account data on first sync, caches in memory, and refreshes on subsequent sync events | Avoids repeated deserialization; single source of truth in-process |
| **Change detection** | Two separate streams: **`languageStream`** (source/target language changed) and **`settingsUpdateStream`** (everything else) | Language changes have heavyweight side-effects (cache clearing, bot option updates, public profile sync) that other setting changes don't need |
| **Side-effect orchestration** | `PangeaController` subscribes to both streams and triggers bot option propagation + public profile sync | Keeps `UserController` focused on data; orchestration lives in the central controller |
| **Migration** | Legacy users stored individual account data keys; a migration path reads those keys and re-saves in the unified format | One-time upgrade, no ongoing cost |

## Entry Points for Changing Settings

### Full settings UI (opens `SettingsLearning`)

1. **Settings page → Learning** — full-page at `/settings/learning`
2. **IGC button long-press** — modal dialog from the writing-assistance button in the chat input
3. **IT bar gear icon** — modal dialog from the interactive translation bar
4. **Analytics language indicator** — modal dialog from the language-pair chip (e.g. "EN → ES") on the learning progress widget

All four use the same `SettingsLearning` widget and the same save flow: write to account data → wait for sync round-trip → stream dispatch → side-effects.

### Per-room bot settings

5. **Bot member menu** — `BotChatSettingsDialog`, opened from the bot's member profile in a room. Updates the profile *and* immediately calls bot option propagation rather than waiting for the stream (avoids perceived lag in the room the user is looking at).

### Inline language-switch prompts

These bypass the full settings UI and only change `targetLanguage`:

6. **Activity session mismatch** — When the user tries to send a message in an activity room whose target language differs from their current L2, a popup offers to switch. Rate-limited to once per 30 minutes per room (via `LanguageMismatchRepo`) to avoid nagging. On confirm, updates the profile and auto-sends the pending message.

7. **Reading toolbar mismatch** — When the user taps a message in a language that doesn't match their L2 and the selected toolbar mode is unavailable, a snackbar offers a "Learn" button to switch their target language.

### Contract all paths must satisfy

Every path that changes settings **must** write to account data via `UserController.updateProfile`. The sync-driven stream is the canonical trigger for propagating changes to the bot and public profile. The only exception is the bot-settings dialog (path 5), which additionally calls bot propagation eagerly for responsiveness.

## Bot Option Propagation

The bot reads the user's settings from a `pangea.bot_options` room state event. The client is responsible for keeping this event current.

### Priority ordering

1. **Bot DM first** — The user's 1:1 chat with the bot is updated first, synchronously, with errors propagating to the caller. This is the room the user is most likely actively using.
2. **Other eligible rooms sequentially** — Updated one-by-one (not in parallel) to avoid Matrix rate-limiting. Individual failures are logged but don't block other rooms.

### Eligible room criteria

A room receives bot option updates if:
- It has a `pangea.bot_options` state event
- It has **no** `pangea.activity_plan` state event (activity rooms manage their own options)
- It has exactly 2 joined members, one of which is the bot

### Retry policy

Each room state write retries up to 3× with exponential backoff (5 s → 10 s → 20 s).

### Known limitation

The activity-plan filter uses state event presence, but Matrix state events persist after an activity ends. Rooms with stale activity plans won't get their options updated. The DM-first strategy mitigates this since the most important room is always covered.

## Public vs. Private Boundary

| Data | Where it lives | Who can see it |
|---|---|---|
| `UserSettings` (language, gender, CEFR, voice, tool toggles) | Matrix account data | Only the owning user |
| `PublicProfileModel` (analytics level/XP, country, about) | Matrix user profile | Anyone in shared rooms |

`country` and `about` are synced from `UserSettings` → `PublicProfileModel` on every settings update. All other settings remain private. Other users see *derived* analytics levels (computed from chat activity), not the self-reported CEFR level.

## Key Files

| Concern | Location |
|---|---|
| Profile / UserSettings models | [lib/pangea/user/user_model.dart](lib/pangea/user/user_model.dart) |
| UserController (cache, streams, updateProfile) | [lib/pangea/user/user_controller.dart](lib/pangea/user/user_controller.dart) |
| Side-effect subscriptions | [lib/pangea/common/controllers/pangea_controller.dart](lib/pangea/common/controllers/pangea_controller.dart) |
| Bot option propagation | [lib/pangea/chat_settings/utils/bot_client_extension.dart](lib/pangea/chat_settings/utils/bot_client_extension.dart) |
| BotOptionsModel | [lib/pangea/chat_settings/models/bot_options_model.dart](lib/pangea/chat_settings/models/bot_options_model.dart) |
| Language mismatch popup + rate limiter | [lib/pangea/learning_settings/](lib/pangea/learning_settings/) |
| Public profile model | [lib/pangea/user/public_profile_model.dart](lib/pangea/user/public_profile_model.dart) |
| Settings UI | [lib/pangea/learning_settings/settings_learning.dart](lib/pangea/learning_settings/settings_learning.dart) |
| Bot chat settings dialog | [lib/pangea/bot/widgets/bot_chat_settings_dialog.dart](lib/pangea/bot/widgets/bot_chat_settings_dialog.dart) |

## Future Work

- **Bio / about editing** — Users currently have no UI to set or edit their `about` field. Add an input to either the learning settings page or a dedicated public-profile editor.
- **Bio / about display** — Decide where other users see the bio. Candidates: user profile sheet in a room, member list hover card, space member directory. Also resolve whether `about` should stay in `UserSettings` (private, synced to public) or move entirely to `PublicProfileModel`.
- **Public learning stats** — Surface vocab count, grammar construct progress, and completed activities on a user's public profile so classmates and teachers can see learning outcomes, not just XP/level.