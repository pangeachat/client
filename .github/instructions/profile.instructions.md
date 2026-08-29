---
applyTo: "lib/features/user/user_model.dart, lib/features/user/user_controller.dart, lib/features/user/public_profile_model.dart, lib/features/user/analytics_profile_model.dart, lib/features/bot/bot_client_extension.dart, lib/features/bot/bot_options_model.dart, lib/features/bot/bot_room_extension.dart, lib/features/bot/widgets/bot_chat_settings_dialog.dart, lib/routes/settings/settings_learning/**, lib/pangea/common/controllers/pangea_controller.dart"
---

# Profile Settings — Architecture & Contracts

How profile settings are structured, stored, propagated, and surfaced to other users.

## Data Model

`Profile` (in [user_model.dart](../../lib/features/user/user_model.dart)) is the top-level container. It wraps three sub-models:

- **`UserSettings`** — learning prefs: target/source language, CEFR level, gender, voice, country, about, etc.
- **`UserToolSettings`** — per-tool on/off toggles (interactive translator, grammar, immersion mode, definitions, auto-WA, autocorrect, and per-surface audio: words, choices, incoming messages).
  - **Device autocorrect default is platform-conditional**: on for Android, where the composer also passes the target language to the keyboard (`hintLocales`) so corrections land in the L2; off on iOS until the keyboard language can be targeted there ([#8465](https://github.com/pangeachat/client/issues/8465)); never on web. The stored value stays unset until the user touches the toggle, so each device resolves its own default and an explicit choice, once made, syncs to every device. Profiles saved before the default flipped keep their stored value ([#8466](https://github.com/pangeachat/client/issues/8466)).
- **`InstructionSettings`** — which instructional tooltips the user has dismissed.

A separate **`PublicProfileModel`** (in [public_profile_model.dart](../../lib/features/user/public_profile_model.dart)) holds data visible to other users: analytics level/XP per language, country, and about. It lives on the Matrix user profile (public), not in account data.

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

7. **The language switcher** is one list of every target language — the same dropdown learning settings uses, so the control behaves identically wherever it is opened. The language shown on the target that opened the switcher is at the top of the list, then the languages the learner already has analytics in (`publicProfile.analytics.languageAnalytics`), each showing its flag and its level, so the two or three languages a learner actually moves between are reachable without scrolling or searching; every other language follows in the usual order below them. Picking one switches immediately.

8. **Send-time mismatch popup** (the backstop) — When the learner tries to send a message in an activity room whose target language differs from their L2, a popup offers to switch, rate-limited to once per 30 minutes per room (via `LanguageMismatchRepo`) to avoid nagging. On confirm it updates the profile and auto-sends the pending message. This stays because the chip is deliberately quiet: it is the only path that reaches a learner who never noticed the mismatch.

9. **Reading toolbar mismatch** — When the user taps a message in a language that doesn't match their L2 and the selected toolbar mode is unavailable, a snackbar offers a "Learn" button to switch their target language.

**Switching to the learner's base language is refused, not attempted.** `IdenticalLanguageException` is thrown inside the profile write, so every offer has to know before it asks: a chip whose language is the learner's L1 renders as a plain label — no tint, no tap — and the switcher shows that language as unavailable with the reason. The send-time popup already applies the same rule.

**A switch is cheap and loses nothing.** Each language keeps its own analytics room and its own local partition ([analytics-system.instructions.md](analytics-system.instructions.md#per-language-isolation)), so switching away banks the current language rather than spending it, and switching back finds it intact; the work of switching is smallest for a language the learner has little history in, which is the common case here. A switch takes effect immediately on tap, with no interstitial confirmation — that held for languages with analytics from the start, and now holds for every language.

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
| `PublicProfileModel` (analytics level/XP, banked stars, country, about) | Matrix user profile | Anyone in shared rooms |

`country` and `about` are synced from `UserSettings` → `PublicProfileModel` on every settings update. All other settings remain private. Other users see *derived* analytics levels (computed from chat activity), not the self-reported CEFR level.

### Ownership and mirroring

`PublicProfileModel` is **per-account state held on a process-wide controller**. `UserController` lives for the life of the app, its `client` getter resolves whichever account is active *now*, and the whole profile is PUT as one blob. That combination is how one learner's bio, country, levels and analytics room ids ended up published on accounts that had set none of them ([#8531](https://github.com/pangeachat/client/issues/8531)).

- **INVARIANT: NEVER publish a profile under an account other than the one it was loaded for.** The loaded profile carries that account's id, and the single write path refuses — and reports — a mismatch. Logout drops it, so the null every writer gates on means "not loaded yet" rather than "loaded, for someone else".
- The mirror is exact, cleared values included: `about` and `country` published equal what `UserSettings` holds, and a cleared one is *removed*. The PUT replaces the whole field object, so omitting a key deletes it server-side. A sync that can only overwrite and never clear cannot converge — it re-writes the stale value on every settings update, which is why a foreign bio survived every later edit.
- **The analytics mirror is keyed per language, by short code** (`fr`, not `fr-CA`). Analytics rooms and local partitions are per language ([analytics-system.instructions.md](analytics-system.instructions.md#per-language-isolation)), so every regional variant of a language shares one XP total and must report one level; a learner who has practised French as `fr`, `fr-FR` and `fr-CA` sees the same level on all three rows. Keying per locale instead gave each variant its own entry over that one shared total, each stuck at whatever the level was the last time that exact variant was the target language ([#8582](https://github.com/pangeachat/client/issues/8582)). Profiles written before that carry per-locale keys; they collapse onto the language when read, the highest level winning.
- **A regional variant never displays a level of its own.** Once the analytics are aggregated onto the language, the language's own row carries the level and the variant rows are ordinary unlabelled options — a level shown against each variant reads as separate progress the learner does not have. For the same reason a variant is never sorted into the analytics group at the top of a target-language list: it would put a row with no level above languages that have one. Variants are legacy data and the levels aggregate down to the language before anything renders them.
- **A published level names the language it was computed from.** A level is derived from one language's analytics across several awaits, so "the language the learner is on right now" is not the same thing as "the language this number describes" — a switch landing in that window published French's level as the learner's Dutch level (#8582).
- **The mirror lags, so nothing showing the learner their own level reads it.** Their own level and XP come from the live local analytics data; the mirror is what *other* people see. Surfaces that do show it — a language row in the switcher or dropdown — read it through the controller's public-profile stream during build, because the profile is mutated in place and a surface holding a stale copy has no way to know. Without that, a corrected level reached whichever surface happened to rebuild next and nothing else, which is how the closed dropdown button and the open list came to disagree (#8582).
- **A published level is only ever written by the analytics update that produced it.** Nothing re-derives and republishes at startup. Reading a level back out of this device's local analytics and publishing it looks safe and is not: the local store is empty on a fresh install, on a new device, and after any reset, and it is only ever brought up to date for the language being studied — so a republish can overwrite a correct published level with one derived from data this device does not have. Until that can be done from data known to be complete, a level left wrong by an earlier bug stays wrong until the learner next earns XP in that language. That is a known gap, accepted deliberately.
- **The published star total counts banked stars for one language.** A star is one orchestrator-awarded activity goal. The total counts saved sessions only, taking the learner's best single run of each activity, for the language that activity was played in. It is deliberately not a course total: what a course-scoped total means depends on that course's activities, and is resolved per course by the progression resolver ([quests.instructions.md](quests.instructions.md)).
- **Only the language being studied is republished.** As with the level, that is the language other people read, and the one this device is best placed to count. Totals published for other languages stay as they are until the learner studies them again.
- **The published total is a high-water mark: it rises and never falls.** Every way the count can come out wrong makes it too *low*, and all of them are ordinary rather than exotic. A device part-way through its first sync is missing rooms. Worse, a session's language is not in room state at all for current activities — the room carries a reference, and the language arrives only once the activity plan is fetched from the choreographer, so an outage or an expired cache leaves those sessions uncounted. Publishing only when the new total is higher makes all of it harmless: an incomplete count is ignored rather than believed, and no completeness check has to be got right.
- **The cost: a total that genuinely falls is never corrected.** Leaving an activity-session room drops the stars earned in it, and the mirror keeps the higher number. The app offers no way to leave one, so this is an edge case rather than a flow — and the higher number is arguably the truer one, since those stars were earned and leaving a room does not unearn them. The learner's own star count, which is recomputed locally and not read from the mirror, can therefore sit below what classmates see.
- **One publish at a time, and never on the startup path.** The whole profile goes up as a single object from several places at once, and concurrent writes are last-one-wins on the server — overlapping them let an older copy land after a newer one and undo it. Publishes are therefore serialized, and a publish still waiting carries any change made while it waited rather than repeating the request. Because they are serialized, nothing that starts the app may *wait* on one: a single slow request would otherwise hold up everything queued behind it, including analytics starting at all.
- **A publish that never answers is abandoned after 30 seconds** so it cannot hold up every publish behind it for the rest of the session. Abandoning it does not recall it, so in that one case a stalled write can still arrive after a later one; the alternative was a queue that stops forever. Nothing retries, so the published profile can sit behind what the app holds until the next change or the next startup.
- **A change is announced the moment it is made, not when its write lands.** Surfaces read the level through the profile stream, and holding the announcement until the write returned would leave them showing the old value for the length of a request — the staleness the stream exists to remove.
- An `analytics_room_id` in the blob must name a room the owning user created. It is not decoration: [join_room_analytics_access_extension.dart](../../lib/features/analytics_access/join_room_analytics_access_extension.dart) reads it to choose the room instructors are granted into, and Synapse refuses a room the caller did not create — so a foreign id leaks nothing, but silently leaves that student's instructors with no analytics access. Ids naming rooms this user does not own are dropped when the profile is loaded; the level beside them is not verifiable and is left to the normal analytics update.

## Key Files

| Concern | Location |
|---|---|
| Profile / UserSettings models | [lib/features/user/user_model.dart](../../lib/features/user/user_model.dart) |
| UserController (cache, streams, updateProfile) | [lib/features/user/user_controller.dart](../../lib/features/user/user_controller.dart) |
| Side-effect subscriptions | [lib/pangea/common/controllers/pangea_controller.dart](../../lib/pangea/common/controllers/pangea_controller.dart) |
| Bot option propagation | [lib/features/bot/bot_client_extension.dart](../../lib/features/bot/bot_client_extension.dart) |
| BotOptionsModel | [lib/features/bot/bot_options_model.dart](../../lib/features/bot/bot_options_model.dart) |
| Language mismatch popup + rate limiter | [lib/routes/settings/settings_learning/](../../lib/routes/settings/settings_learning/) |
| Public profile model | [lib/features/user/public_profile_model.dart](../../lib/features/user/public_profile_model.dart) |
| Public profile display (about, level, country) | [lib/widgets/users/](../../lib/widgets/users/) |
| Analytics-room grant that reads the public profile | [lib/features/analytics_access/join_room_analytics_access_extension.dart](../../lib/features/analytics_access/join_room_analytics_access_extension.dart) |
| Settings UI | [lib/routes/settings/settings_learning/settings_learning.dart](../../lib/routes/settings/settings_learning/settings_learning.dart) |
| Profile page (avatar, country, gender, about) | [lib/routes/profile/user_home_page.dart](../../lib/routes/profile/user_home_page.dart) |
| Bot chat settings dialog | [lib/features/bot/widgets/bot_chat_settings_dialog.dart](../../lib/features/bot/widgets/bot_chat_settings_dialog.dart) |

## Future Work

- **First-switch confirmation for analytics-less languages** — a switch into a language with no analytics currently behaves like any other: immediate, no interstitial. We may want to say once that the new language starts at level 1 and the previous one keeps its level and XP, so an empty progress screen never reads as lost work — deferred rather than built for the initial context-switching rollout.
- **Per-language self-reported level** — `UserSettings.cefrLevel` is one value per learner while analytics level and XP are per language, so switching leaves a level asserted about the new language that the learner never claimed. The more switching we encourage from context, the more often that is wrong.
- **Where `about` and `country` live** — both are edited on the profile page and published to `PublicProfileModel`, so they cross the private → public boundary through a sync that has to be kept exact in both directions. Moving them into `PublicProfileModel` outright, edited in a public-profile editor, would remove the mirror rather than keep fixing it.
- **Public learning stats** — Surface vocab count, grammar construct progress, and completed activities on a user's public profile so classmates and teachers can see learning outcomes, not just XP/level.