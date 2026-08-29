---
applyTo: "lib/features/analytics/**,lib/features/analytics_data/**,lib/routes/analytics/**,lib/routes/chat/chat_details/space_analytics/**"
---

# Analytics System

The analytics system tracks learning, rewards progress, visualizes growth, and guides the delivery of content like practice exercises, activity suggestions, and distractor generation. Every word a user encounters — through chatting, reading, or practicing — grows from a seed into a flower. 

## Design Goals

1. **Instant feedback**: Users should see XP and growth animations the moment they interact with a word, not after a server round-trip. The system is local-first.
2. **Every interaction counts**: Every interaction, from reading a message to tapping a new word to practice exercises, contributes to the user's progress.
3. **Engaging visuals**: The seeds→greens→flowers metaphor and per-word emoji associations make progress tangible and fun to track.
4. **Fun, personalized practice**: Practice exercises are generated from the user's actual messages, making them relevant and engaging. The system prioritizes words that need attention, not just random drills.
5. **Teacher insights**: Teachers can view aggregate analytics for their students, helping them tailor instruction and identify who needs extra support.

## Constructs
The core unit of analytics is a **construct** — either a vocabulary word, chunk, grammar pattern, or even higher-level concepts (see [`ConstructIdentifier`](../../lib/features/analytics/construct_identifier.dart)). It's basically anything you can track and is interesting for learning. Each construct has a unique identifier, a type (vocab vs morph), and tracks how many times the user has encountered it, practiced it, and mastered it. 

### Two Kinds of Constructs

Defined by [`ConstructTypeEnum`](../../lib/features/analytics/construct_type_enum.dart):

| Type | UI Label | What It Tracks | Example |
|------|----------|----------------|--------|
| Vocab | "Vocabulary" | Individual words identified by lemma + part of speech | "run" (verb), "bank" (noun) |
| Morph | "Grammar" | Morphological features of words (categories from [`MorphFeaturesEnum`](../../lib/pangea/morphs/morph_features_enum.dart)) | Tense=Past, Number=Plural |

The user sees these as two tabs in their analytics view. Grammar constructs "unlock" when they reach the Green stage (50 XP), giving users a sense of discovery.

### What Earns XP

Different interactions contribute different amounts of XP, reflecting effort. Each interaction type is a value in [`ConstructUseTypeEnum`](../../lib/features/analytics/construct_use_type_enum.dart), which determines how much XP it awards:

- **Clicking a new word** in the toolbar (first view) — small XP (passive learning)
- **Correct practice answers** (emoji matching, meaning selection, listening) — moderate XP
- **Wrong practice answers** — a small negative XP value, deliberately, to discourage guessing through a multiple-choice item. Skipped or unanswered items are worth 0. See `ConstructUseTypeEnum.pointValue` for the per-type values.
- **Using a word in writing** (via the choreographer) — XP based on the construct use type
- **Hearing a word** through read-aloud or voice-message playback — 0 XP. The exposure is the data; see [Listening exposure](#listening-exposure).

Each data point is stored as a [`OneConstructUse`](../../lib/features/analytics/constructs_model.dart) which includes construct identifier, use type and timestamp, plus — for message-originated uses only — the message id. Listening exposure carries neither a message id nor a room id; see [Listening exposure](#listening-exposure).

Adding a value to `ConstructUseTypeEnum` is a bigger commitment than it looks: it lands in XP, in the skill rows, in the teacher summaries and in practice selection. Work through [Adding a use type](#adding-a-use-type) before writing one.

### Adding a use type

The compiler asks most of these — the switches over `ConstructUseTypeEnum` are exhaustive, so a new value will not build until they are answered. It does **not** ask the last two, and those are the ones that have been got wrong.

1. **XP value** (`pointValue`) — and whether 0 is right, which means the use is recorded for its own sake rather than rewarded.
2. **Skill** (`skillsEnumType`) — which row of the construct details page it belongs in.
3. **Produced or received** (`sentByUser`) — this is what keeps a use out of the turn and typed-word counters.
4. **Summary bucket** (`summaryEnumType`) — correct, incorrect, typed word, or `null` for none. Note that [`SpaceAnalyticsSummaryModel`](../../lib/routes/chat/chat_details/space_analytics/space_analytics_summary_model.dart) has a second split that keys on the SIGN of `xp` rather than on this enum, so a 0-XP use needs handling there too.
5. **Language provenance** — *what language is this use in, and how does the recording path know?* Not asked by any compiler. See [Per-Language Isolation](#per-language-isolation): the language must travel with the recording as a required argument, from whatever knows what was actually written, read or spoken.
6. **Volume** — how often does this fire relative to production and practice? Nothing in the store prunes or compacts uses, so a high-frequency use type needs bucketing rather than one row per event, and the display has to stay readable at its volume.

### Listening exposure

Receptive exposure per word is a variable language researchers design studies around, so hearing a lemma is recorded as a construct use in its own right (`ConstructUseTypeEnum.hrd`). It is **worth 0 XP** — awarding points for audio the learner did not ask for would be XP inflation, and the count is what the data is for. It is vocab-only and gated on `lemma.saveVocab`, the same filter every other lemma-level signal uses.

Every read-aloud surface mints it, not just whole messages: word taps and practice-choice audio are listening too. That deliberately overlaps `click` and the `corWL` / `corLA` family, which record the same moment for different reasons — one counts what was heard, the others what was looked up or answered. Exposure is minted only on a **completed** playback, because read-aloud holds a single slot and stops on drafting, selection and focus loss; minting at the start would bank words that were never spoken.

An exposure use **never carries a source event id or room id.** The listening lane drops both at the point of collection on the grounds that a per-student record of which peers a learner attends to is a social-graph fact about a third party (see [`DosageAudioEvent`](../../lib/features/dosage/dosage_audio_event.dart)), and a lemma-level record derived from someone else's message would reintroduce exactly that, with content attached. Changing this is a privacy decision, not a schema decision.

Exposure is excluded from `sentByUser` and returns `null` from `summaryEnumType`, so it reaches neither the typed-words counter nor the correct/incorrect buckets: it is neither. The bucket split in [`SpaceAnalyticsSummaryModel`](../../lib/routes/chat/chat_details/space_analytics/space_analytics_summary_model.dart) keys on the sign of `xp` rather than on that enum, so it needs its own guard there — a 0-XP use otherwise lands in *incorrect*.

**Bucketing.** Exposure fires far more often than production or practice, and nothing in the analytics store ever prunes or compacts uses. So exposures accumulate in memory ([`ListeningExposureBuffer`](../../lib/features/analytics/listening_exposure_buffer.dart)) and are written as one row per lemma per window carrying an explicit `count`, rather than one row per event. The count is authoritative — never infer it from the number of rows.

The window is **five minutes**, and its ceiling is not arbitrary: construct-use timestamps double as corroboration anchors for engagement spans, matched within ±10 minutes with no type filter. A bucket therefore carries a real instant inside itself (its last exposure), never a synthetic boundary, and the window must stay inside the corroboration window — a day-long bucket would carry one anchor and stop vouching for the rest of the day, which bites hardest in the passive listening session where exposure rows are the only anchors a learner has.

### Construct Deduplication

The same word can appear with different casing or slight variations across messages (e.g., "Hello" vs "hello"). [`ConstructMergeTable`](../../lib/features/analytics_data/construct_merge_table.dart) merges these transparently so the user sees one unified progress bar per word, not confusing duplicates.

### Construct Displays

Users can view their analytics via the [ConstructAnalyticsView](../../lib/routes/analytics/construct_analytics/analytics_details_popup.dart). There are pages for vocab and morph constructs. Each construct type has a list page, displaying all constructs, and an individual construct details page, which the user can navigate to via the main list.

The morph list view ([MorphAnalyticsListView](../../lib/routes/analytics/construct_analytics/morph_analytics_list_view.dart)) displays a list of grammar feature sections, each containing tiles for each of the grammar tags in that feature. All features / tags for the user's L2 are displayed, with a 'locked/disabled' indicator for unused tags. (See [grammar analytics instructions](grammar-analytics.instructions.md) for more details.)

The vocab list view shows a list of tiles, one for each vocab construct, each with the construct's assigned emoji (if present) and the construct's lemma (the vocab word itself). The lemma's text color indicates the construct's [level](../../lib/features/analytics/construct_level_enum.dart). The page has filters for each construct level, and a search bar. Vocab construct tiles can be long-pressed to select them for deletion (see [Blocking Constructs](#blocking-constructs) for more details on blocking vocab constructs). 

Both list views show a button at the top to launch practice (See [practice exercises instructions](practice-exercises.instructions.md) for more details on analytics practice exercises), and a "more" button which expands a popup menu containing additional options, e.g. the download button, a button to navigate to the blocked constructs page, etc. The "more" button is hidden if it has no content, like in a morph construct list with developer mode turned off.

Construct details pages show definitions, canonical examples, and user-generated usage examples for individual constructs.

On a construct details page each usage row (one per learning skill, on vocab and grammar cards alike) shows one counter chip per score bucket ([`LemmaUsageChips`](../../lib/routes/analytics/construct_analytics/construct_analytics_details/lemma_usage_chips.dart)): a green check counts uses that earned XP, a red cross counts uses that lost it, and a grey hollow dot counts uses that scored nothing. Each chip carries its icon so the buckets stay tellable apart without color, and a screen-reader label saying the same thing in words. Chips count all uses rather than the capped prefix that stops at the flower cap, because a counter frozen at ×34 while the learner keeps using the word reads as broken. Grey is not noise: `ignIGC` and `ignIt` are minted on every sent message for tokens writing assistance left alone, so they are the bulk of the Writing row's grey count, and a word the learner typed correctly would read as an empty row without them.

Listening exposure is the one exclusion, and it is excluded **by use type, not by being worth nothing** — hearing a word is something that happened to the learner, not a use that failed to score, so it appears as its own chip on the listening row: a speaker icon in the app's primary color, never the grey of an unscored use. Anything added later that fires at exposure's frequency belongs in the same shape. Excluding it by score instead would silently take the grey counts above with it.

### Blocking Constructs

Users can hide specific constructs they consider too easy or irrelevant (e.g., cognates, proper nouns). Blocked constructs:
- Disappear from all analytics views except the blocked vocab constructs page (described later in this section)
- Stop contributing to XP totals
- Are excluded from practice exercise selection
- Persist across sessions via the Matrix analytics room

Within the code, this is referred to as "Blocking," and undoing the block is referred to as "Restoring." Within the UI, the terms are "Deleting" and "Restoring." This hides the implementation details from the user (making blocked constructs appear to be deleted), while keeping the terminology of the internal system consistent (nothing is literally 'deleted,' but is instead 'blocked' from the user's view). Blocking a construct does not prevent new construct uses from being generated or collected. They are hidden from the user, but continue to be stored in the background.

Only vocab constructs can be blocked. Morph constructs cannot be blocked.

Blocked Constructs are stored in [PangeaEventTypes.analyticsSettings](../../lib/routes/chat/events/constants/pangea_event_types.dart) events in the analytics room of their corresponding language as a list of ConstructIdentifiers. Blocking constructs adds them to this list, so constructs can be blocked one at a time or in bulk with one write to the state event. This is also true of restoring constructs.

Vocab constructs can be blocked individually from construct details pages via the delete button at the bottom of the page, or in bulk via the vocab construct list page by long pressing a construct tile to enter selection mode, selecting constructs to block, and then clicking the delete button at the top of the page. The delete button is only visible in select mode.

Users can restore constructs in the blocked vocab constructs page, or in construct details pages for blocked constructs. 

The blocked vocab constructs page is accessed by the "more" dropdown button in the AppBar of the vocab construct list view. This page looks similar to the vocab construct list view, but is missing the filters, search bar, practice button, and dropdown menu. This page has its own route (analytics:vocab/deleted), separate from the main vocab construct list. Long-pressing a vocab construct tile in this view activates select mode, so vocab constructs can be bulk restored. Clicking a vocab tile in this view opens the construct details page, just like the vocab construct list. The tiles have lower opacity than the normal vocab construct tiles, and carry no per-tile blocked badge — every tile on this page is blocked, so a badge marks nothing the page title doesn't already say. Dimming does not reach a screen reader, so each tile names its blocked status in its accessible name instead.

Blocked constructs can also be restored from the construct details page. This page can be reached by clicking on a construct tile in the blocked vocab constructs page, or by clicking on the title of a word card for a blocked construct. Word cards for blocked constructs have a lower opacity title with a red "restore" icon button in the top right corner (instead of the flag button) that restores the construct when tapped. Blocked constructs show a "restore" button at the bottom of the page instead of a delete button.

When a vocab construct is restored, its XP is added back to the total language XP silently. No XP gained or level up events are fired, so no animations or other effects are shown.

Blocking constructs adds a [AnalyticsStreamUpdate](../../lib/features/analytics_data/analytics_data_service.dart) containing a set of newly blocked constructs to the analytics update dispatcher's [constructUpdateStream](../../lib/features/analytics_data/analytics_update_dispatcher.dart), which widgets can listen to when they need to react to blocked construct updates (e.g., the vocab construct list listens to it to filter blocked constructs from the list). Restoring constructs does something similar, except these updates contain a set of the newly restored constructs. The blocked vocab constructs page listens to these updates to filter out restored constructs. These are separate variables in the AnalyticsStreamUpdate because widgets have to react differently to these types of updates. 

## User Levels

Total XP across all constructs determines the user's global level, computed in [`DerivedAnalyticsDataModel`](../../lib/features/analytics_data/derived_analytics_data_model.dart). The progression is quadratic — early levels come quickly to create momentum, while later levels require sustained effort:

$$\text{level} = \lfloor 1 + \sqrt{\frac{1 + 8 \cdot \text{totalXP} / 300}{2}} \rfloor$$

Level-ups are **celebration moments**: the app shows [LevelUpBadgeCelebration](../../lib/routes/world/level_up_badge_celebration.dart) – a badge pulse plus a "Level N!" chip.

> This formula is still being balanced to find the optimal sequence of effort and reward.

### Level Protection

Users should never see their level go down due to negative-XP construct uses. If adding new, negative-points construct uses would reduce total XP below the current level threshold, the system applies an XP offset to maintain the level. This is a deliberate UX choice — level-downs feel bad and discourage experimentation.

## Data Architecture Principles

### Local-First, Sync-Later

All analytics computation happens against [`AnalyticsDatabase`](../../lib/features/analytics_data/analytics_database.dart) (SQLite on native, IndexedDB on web). The app never queries the server for analytics on a per-message basis. [`AnalyticsUpdateService`](../../lib/features/analytics_data/analytics_update_service.dart) syncs data to a dedicated Matrix room in the background — batched every 10 messages or 10 minutes, whichever comes first. [`AnalyticsDataService`](../../lib/features/analytics_data/analytics_data_service.dart) is the central orchestrator that wires everything together.

### Per-Language Isolation

Each target language has its own analytics room and its own local database partition. Switching languages reinitializes the analytics context cleanly.

Every construct use is filed under exactly one language, and that language comes from the **source of the use** — the text that was written, read or spoken. **NEVER record a use whose language you have not established**, and in particular never let it default to whatever L2 the learner happens to have set: a stored use carries no language of its own, so once it is written into the wrong language's room nothing downstream can tell it apart from a real one. Mislabeled data is worse than absent data, because absent data is visible as a gap.

A new source of construct uses therefore has to answer *how do you know what language this is in* before it records anything, and the answer belongs in the code as a required argument rather than as a check each call site is trusted to remember — see [Adding a use type](#adding-a-use-type).

### Multi-Device Sync

Because analytics are stored in Matrix rooms, they sync across devices automatically via the Matrix sync protocol. On login or language change, [`AnalyticsSyncController`](../../lib/features/analytics_data/analytics_sync_controller.dart) performs a bulk catch-up from the analytics room before starting real-time tracking.

## Celebration Moments

[`AnalyticsUpdateDispatcher`](../../lib/features/analytics_data/analytics_update_dispatcher.dart) emits [typed events](../../lib/features/analytics_data/analytics_update_events.dart) that the UI listens for to trigger celebratory animations:

| Event | UX Response |
|-------|-------------|
| [`XPGainedEvent`](../../lib/features/analytics_data/analytics_update_events.dart) | Floating "+N" animation anchored to the word the user interacted with |
| [`ConstructLevelUpEvent`](../../lib/features/analytics_data/analytics_update_events.dart) | Growth animation on the word's token in the toolbar |
| [`LevelUpEvent`](../../lib/features/analytics_data/analytics_update_events.dart) | Full-screen banner + chime + AI-generated learning summary |
| [`MorphUnlockedEvent`](../../lib/features/analytics_data/analytics_update_events.dart) | Notification that a new grammar pattern has been discovered |
| [`NewConstructsEvent`](../../lib/features/analytics_data/analytics_update_events.dart) | Subtle highlight (first-ever interaction with a word) |

These events are always anchored to a specific UI element (via a `targetID`) so the animation appears in context, not as a disconnected popup. Use the [`AnalyticsUpdater`](../../lib/features/analytics_data/analytics_updater_mixin.dart) mixin on any widget that triggers analytics and wants to show immediate XP/growth feedback.

## Analytics for Teachers (Space Analytics)

Teachers/space admins can view aggregate analytics for their students:
- Download summaries per student or per space
- See inactive student indicators
- Request detailed analytics reports

This data flows from each student's analytics room to the teacher view — the teacher never sees raw construct data, only aggregated summaries.

## Key Contracts

- **Never fetch analytics from Synapse per-message.** The local database is the runtime source of truth.
- **XP per construct caps at the flower threshold (100).** [`ConstructUses.cappedUses`](../../lib/features/analytics/construct_use_model.dart) enforces this, preventing level inflation from repeatedly encountering familiar words.
- **Level can never visibly decrease due to negative-XP construct uses**. Use offsets to maintain. Level may visibly decrease due to users blocking constructs.
- **The "other" category is always filtered out** of aggregations and displays. It represents unclassifiable tokens.
- **Analytics initialization must complete before any UI reads.** All public methods await an init completer.
- **A UI surface reads live analytics through the update streams, subscribed during build — not via a listener attached after mount.** [`AnalyticsUpdateDispatcher`](../../lib/features/analytics_data/analytics_update_dispatcher.dart) fires its first construct/activity update once, during init, on hot broadcast streams with no replay. A widget that subscribes *after* init completes (a manual `listen` in `didChangeDependencies`) misses that event and shows stale/zero until the next live update. Read inside a `StreamBuilder` on the construct/activity streams — which subscribes during build, before init finishes — and read `numConstructs`/`derivedData` *inside* the builder so each rebuild is fresh. The world map's top-right cluster (see [routing.instructions.md](routing.instructions.md)) follows this: [`WorldUserCluster`](../../lib/routes/world/world_user_cluster.dart) (`_PowerupsPill`) and [`WorldAnalyticsBar`](../../lib/routes/world/world_analytics_bar.dart) (`_PowerupsRow`) each `StreamBuilder` on the construct stream in `build` and read the counts and `derivedData` inside the builder; [`AnalyticsHeaderAvatarInternal`](../../lib/routes/world/analytics_header_avatar.dart) reads `derivedData` (with the cached fallback) inside its build-time builder the same way.
- **Show level/XP from the local `derivedData`, not the public-profile level.** [`AnalyticsDataService`](../../lib/features/analytics_data/analytics_data_service.dart) `derivedData` (with `cachedDerivedDataFor` as the synchronous fallback) reflects the live local XP total; the public-profile `AnalyticsProfileModel.level` can lag behind it.
- **Construct uses store `eventId` and `roomId` when they originate from a message context.** Chat-originated uses (wa, ga, ta) and message-practice uses populate both fields, enabling tracing back to the source message. Standalone practice uses (e.g., from the analytics practice page) correctly set these to null — there is no originating room/message in that context.

## Open Issues Discussions
*Last updated: 2026-02-15*

- [#5675](https://github.com/pangeachat/client/issues/5675) — Rethink grammar analytics tab: filter irrelevant morph features per language pair, simplify UI for non-linguists
- [#5506](https://github.com/pangeachat/client/discussions/5506) — Define key outcomes to track and why (analytics strategy)
- [#4958](https://github.com/pangeachat/client/discussions/4958) — Implement repetition decay for per-user XP scoring
- [#4959](https://github.com/pangeachat/client/discussions/4959) — Ensure "minutes per day" is being collected in analytics
- [#5300](https://github.com/pangeachat/client/discussions/5300) — Some grammar types have no data (construct coverage gaps)
- [#4947](https://github.com/pangeachat/client/discussions/4947) — Hard to tell where Activity Ping is coming from (analytics event clarity)
- [#4742](https://github.com/pangeachat/client/discussions/4742) — Way to sort vocab words in analytics
- [#4397](https://github.com/pangeachat/client/discussions/4397) — Link vocab detail sentences to actual chat messages for practice
- [#5252](https://github.com/pangeachat/client/discussions/5252) — Show construct emoji change when XP earning triggers it
- [#3569](https://github.com/pangeachat/client/discussions/3569) — Practice exercises in the analytics page

