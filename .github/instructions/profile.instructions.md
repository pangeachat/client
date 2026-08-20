---
applyTo: "lib/pangea/user/user_model.dart, lib/pangea/user/user_controller.dart, lib/pangea/user/public_profile_model.dart, lib/pangea/user/analytics_profile_model.dart, lib/pangea/chat_settings/utils/bot_client_extension.dart, lib/pangea/chat_settings/models/bot_options_model.dart, lib/pangea/bot/utils/bot_room_extension.dart, lib/pangea/bot/widgets/bot_chat_settings_dialog.dart, lib/pangea/learning_settings/**, lib/pangea/common/controllers/pangea_controller.dart"
---

# Profile Settings — Architecture & Contracts

How profile settings are structured, stored, propagated, and surfaced to other users.

## Data Model

`Profile` (in [user_model.dart](lib/pangea/user/user_model.dart)) is the top-level container. It wraps three sub-models:

- **`UserSettings`** — learning prefs: target/source language, CEFR level, gender, voice, country, about, etc.
- **`UserToolSettings`** — per-tool on/off toggles (interactive translator, grammar, immersion mode, definitions, auto-WA, autocorrect, and per-surface audio: words, choices, incoming messages).
  - **Device autocorrect default is platform-conditional**: on for Android, where the composer also passes the target language to the keyboard (`hintLocales`) so corrections land in the L2; off on iOS until the keyboard language can be targeted there ([#8465](https://github.com/pangeachat/client/issues/8465)); never on web. The stored value stays unset until the user touches the toggle, so each device resolves its own default and an explicit choice, once made, syncs to every device. Profiles saved before the default flipped keep their stored value ([#8466](https://github.com/pangeachat/client/issues/8466)).
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
2. **Writing-assistance button long-press** — modal dialog from the writing-assistance button in the chat input
3. **IT bar gear icon** — modal dialog from the interactive translation bar
4. **Analytics language indicator** — modal dialog from the language-pair chip (e.g. "EN → ES") on the learning progress widget

All four use the same `SettingsLearning` widget and the same save flow: write to account data → wait for sync round-trip → stream dispatch → side-effects.

### Per-room bot settings

5. **Bot member menu** — `BotChatSettingsDialog`, opened from the bot's member profile in a room. Updates the profile *and* immediately calls bot option propagation rather than waiting for the stream (avoids perceived lag in the room the user is looking at).

### Switching from context

Course and activity content is language-specific, but the learner's language is one global setting. Power users in multiple courses can often encounter content outside of their L2. Switching out of that mismatch is meant to be easy and low-stakes, and it happens **from the surface the learner is already looking at** rather than from settings.

6. **The language chip is the switch.** Every surface that shows what language its content is in draws that language already, and that drawing is the control: the [`LanguageFlagChip`](../../lib/features/languages/language_flag_chip.dart) in the activity start page's info row, the language chip among a course's info chips (both the course a learner has joined and one they are previewing), and the same chip in a running session's [goal header](activities.instructions.md#the-goal-header). When the content's language differs from the learner's L2 the chip is tinted to say so; tapping it opens the language switcher. Nothing fires on open — these panels re-open on nearly every move through the workspace, so an offer that appeared by itself would be a notification the learner cannot turn off.

7. **The language switcher** is one list of every target language — the same dropdown learning settings uses, so the control behaves identically wherever it is opened. The languages the learner already has analytics in (`publicProfile.analytics.languageAnalytics`) sort to the top, each showing its flag and its level, so the two or three languages a learner actually moves between are reachable without scrolling or searching; every other language follows in the usual order below them. Picking one switches immediately and offers **Undo** in a snackbar.

8. **Send-time mismatch popup** (the backstop) — When the learner tries to send a message in an activity room whose target language differs from their L2, a popup offers to switch, rate-limited to once per 30 minutes per room (via `LanguageMismatchRepo`) to avoid nagging. On confirm it updates the profile and auto-sends the pending message. This stays because the chip is deliberately quiet: it is the only path that reaches a learner who never noticed the mismatch.

9. **Reading toolbar mismatch** — When the user taps a message in a language that doesn't match their L2 and the selected toolbar mode is unavailable, a snackbar offers a "Learn" button to switch their target language.

**Switching to the learner's base language is refused, not attempted.** `IdenticalLanguageException` is thrown inside the profile write, so every offer has to know before it asks: a chip whose language is the learner's L1 renders as a plain label — no tint, no tap — and the switcher shows that language as unavailable with the reason. The send-time popup already applies the same rule.

**A switch is cheap and loses nothing.** Each language keeps its own analytics room and its own local partition ([analytics-system.instructions.md](analytics-system.instructions.md#per-language-isolation)), so switching away banks the current language rather than spending it, and switching back finds it intact; the work of switching is smallest for a language the learner has little history in, which is the common case here. The first switch into a language with no analytics at all says so once — the new language starts at level 1, the previous one keeps its level and XP — so an empty progress screen never reads as lost work.

### Contract all paths must satisfy

Every path that changes settings **must** write to account data via `UserController.updateProfile` — the chip and the switcher included, however far they sit from the settings page. The sync-driven stream is the canonical trigger for propagating changes to the bot and public profile. The only exception is the bot-settings dialog (path 5), which additionally calls bot propagation eagerly for responsiveness.

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

- **Per-language self-reported level** — `UserSettings.cefrLevel` is one value per learner while analytics level and XP are per language, so switching leaves a level asserted about the new language that the learner never claimed. The more switching we encourage from context, the more often that is wrong.
- **Bio / about editing** — Users currently have no UI to set or edit their `about` field. Add an input to either the learning settings page or a dedicated public-profile editor.
- **Bio / about display** — Decide where other users see the bio. Candidates: user profile sheet in a room, member list hover card, space member directory. Also resolve whether `about` should stay in `UserSettings` (private, synced to public) or move entirely to `PublicProfileModel`.
- **Public learning stats** — Surface vocab count, grammar construct progress, and completed activities on a user's public profile so classmates and teachers can see learning outcomes, not just XP/level.