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
- **Wrong practice answers** — reduced or zero XP (no punishment, but less reward)
- **Using a word in writing** (via the choreographer) — XP based on the construct use type

Each data point is stored as a [`OneConstructUse`](../../lib/features/analytics/constructs_model.dart) which includes construct identifier, use type, timestamp, and messageId.

### Construct Deduplication

The same word can appear with different casing or slight variations across messages (e.g., "Hello" vs "hello"). [`ConstructMergeTable`](../../lib/features/analytics_data/construct_merge_table.dart) merges these transparently so the user sees one unified progress bar per word, not confusing duplicates.

### Construct Displays

Users can view their analytics via the [ConstructAnalyticsView](../../lib/routes/analytics/construct_analytics/analytics_details_popup.dart). There are pages for vocab and morph constructs. Each construct type has a list page, displaying all constructs, and an individual construct details page, which the user can navigate to via the main list.

The morph list view ([MorphAnalyticsListView](../../lib/routes/analytics/construct_analytics/morph_analytics_list_view.dart)) displays a list of grammar feature sections, each containing tiles for each of the grammar tags in that feature. All features / tags for the user's L2 are displayed, with a 'locked/disabled' indicator for unused tags. (See [grammar analytics instructions](grammar-analytics.instructions.md) for more details.)

The vocab list view shows a list of tiles, one for each vocab construct, each with the construct's assigned emoji (if present) and the construct's lemma (the vocab word itself). The lemma's text color indicates the construct's [level](../../lib/features/analytics/construct_level_enum.dart). The page has filters for each construct level, and a search bar. Vocab construct tiles can be long-pressed to select them for deletion (see [Blocking Constructs](#blocking-constructs) for more details on blocking vocab constructs). 

Both list views show a button at the top to launch practice (See [practice exercises instructions](practice-exercises.instructions.md) for more details on analytics practice exercises), and a "more" button which expands a popup menu containing additional options, e.g. the download button, a button to navigate to the blocked constructs page, etc. The "more" button is hidden if it has no content, like in a morph construct list with developer mode turned off.

Construct details pages show definitions, canonical examples, and user-generated usage examples for individual constructs.

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

Each target language has its own analytics room and its own local database partition. Switching languages reinitializes the analytics context cleanly. There is no cross-language XP blending.

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
- **A UI surface reads live analytics through the update streams, subscribed during build — not via a listener attached after mount.** [`AnalyticsUpdateDispatcher`](../../lib/features/analytics_data/analytics_update_dispatcher.dart) fires its first construct/activity update once, during init, on hot broadcast streams with no replay. A widget that subscribes *after* init completes (a manual `listen` in `didChangeDependencies`) misses that event and shows stale/zero until the next live update. Read inside a `StreamBuilder` on the construct/activity streams — which subscribes during build, before init finishes — and read `numConstructs`/`derivedData` *inside* the builder so each rebuild is fresh. The chat-list `LearningProgressIndicators` and the world map's top-right cluster (see [routing.instructions.md](routing.instructions.md)) both follow this.
- **Show level/XP from the local `derivedData`, not the public-profile level.** [`AnalyticsDataService`](../../lib/features/analytics_data/analytics_data_service.dart) `derivedData` (with `cachedDerivedData` as the synchronous fallback) reflects the live local XP total; the public-profile `AnalyticsProfileModel.level` can lag behind it.
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

