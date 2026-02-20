---
applyTo: "lib/pangea/analytics_data/**,lib/pangea/analytics_misc/**,lib/pangea/analytics_page/**,lib/pangea/analytics_summary/**,lib/pangea/analytics_practice/**,lib/pangea/analytics_settings/**,lib/pangea/analytics_downloads/**,lib/pangea/analytics_details_popup/**,lib/pangea/space_analytics/**,lib/pangea/constructs/**"
---

# Analytics System

The analytics system tracks learning, rewards progress, visualizes growth, and guides the delivery of content like practice exercises, activity suggestions, and distractor generation. Every word a user encounters — through chatting, reading, or practicing — grows from a seed into a flower. 

## Design Goals

1. **Instant feedback**: Users should see XP and growth animations the moment they interact with a word, not after a server round-trip. The system is local-first.
2. **Every interaction counts**: Every interaction, from reading a message to tapping a new word to practice exercises, contributes to the user's progress.
3. **Engaging visuals**: The seeds→greens→flowers metaphor and per-word emoji associations make progress tangible and fun to track.
4. **Fun, personalized practice**: Practice activities are generated from the user's actual messages, making them relevant and engaging. The system prioritizes words that need attention, not just random drills.
5. **Teacher insights**: Teachers can view aggregate analytics for their students, helping them tailor instruction and identify who needs extra support.

## Constructs
The core unit of analytics is a **construct** — either a vocabulary word, chunk, grammar pattern, or even higher-level concepts (see [`ConstructIdentifier`](lib/pangea/constructs/construct_identifier.dart)). It's basically anything you can track and is interesting for learning. Each construct has a unique identifier, a type (vocab vs morph), and tracks how many times the user has encountered it, practiced it, and mastered it. 

### Two Kinds of Constructs

Defined by [`ConstructTypeEnum`](lib/pangea/analytics_misc/construct_type_enum.dart):

| Type | UI Label | What It Tracks | Example |
|------|----------|----------------|--------|
| Vocab | "Vocabulary" | Individual words identified by lemma + part of speech | "run" (verb), "bank" (noun) |
| Morph | "Grammar" | Morphological features of words (categories from [`MorphFeaturesEnum`](lib/pangea/morphs/morph_features_enum.dart)) | Tense=Past, Number=Plural |

The user sees these as two tabs in their analytics view. Grammar constructs "unlock" when they reach the Green stage (50 XP), giving users a sense of discovery.

### What Earns XP

Different interactions contribute different amounts of XP, reflecting effort. Each interaction type is a value in [`ConstructUseTypeEnum`](lib/pangea/analytics_misc/construct_use_type_enum.dart), which determines how much XP it awards:

- **Clicking a new word** in the toolbar (first view) — small XP (passive learning)
- **Correct practice answers** (emoji matching, meaning selection, listening) — moderate XP
- **Wrong practice answers** — reduced or zero XP (no punishment, but less reward)
- **Using a word in writing** (via the choreographer) — XP based on the construct use type

Each data point is stored as a [`OneConstructUse`](lib/pangea/analytics_misc/constructs_model.dart) which includes construct identifier, use type, timestamp, and messageId.

### Construct Deduplication

The same word can appear with different casing or slight variations across messages (e.g., "Hello" vs "hello"). [`ConstructMergeTable`](lib/pangea/analytics_data/construct_merge_table.dart) merges these transparently so the user sees one unified progress bar per word, not confusing duplicates.

### Blocking Constructs

Users can hide specific constructs they consider too easy or irrelevant (e.g., cognates, proper nouns). Blocked constructs:
- Disappear from all analytics views
- Stop contributing to XP totals
- Are excluded from practice activity selection
- Persist across sessions via the Matrix analytics room

## User Levels

Total XP across all constructs determines the user's global level, computed in [`DerivedAnalyticsDataModel`](lib/pangea/analytics_data/derived_analytics_data_model.dart). The progression is quadratic — early levels come quickly to create momentum, while later levels require sustained effort:

$$\text{level} = \lfloor 1 + \sqrt{\frac{1 + 8 \cdot \text{totalXP} / 300}{2}} \rfloor$$

Level-ups are **celebration moments**: the app shows a banner, plays a chime, and [`LevelUpAnalyticsService`](lib/pangea/analytics_data/level_up_analytics_service.dart) generates an AI summary of what the user learned since their last level-up (pulling from actual messages they sent and received).

> This formula is still being balanced to find the optimal sequence of effort and reward.

### Level Protection

Users should never see their level go down from routine actions. If blocking a construct or switching languages would reduce total XP below the current level threshold, the system applies an XP offset to maintain the level. This is a deliberate UX choice — level-downs feel bad and discourage experimentation.

## Data Architecture Principles

### Local-First, Sync-Later

All analytics computation happens against [`AnalyticsDatabase`](lib/pangea/analytics_data/analytics_database.dart) (SQLite on native, IndexedDB on web). The app never queries the server for analytics on a per-message basis. [`AnalyticsUpdateService`](lib/pangea/analytics_data/analytics_update_service.dart) syncs data to a dedicated Matrix room in the background — batched every 10 messages or 10 minutes, whichever comes first. [`AnalyticsDataService`](lib/pangea/analytics_data/analytics_data_service.dart) is the central orchestrator that wires everything together.

### Per-Language Isolation

Each target language has its own analytics room and its own local database partition. Switching languages reinitializes the analytics context cleanly. There is no cross-language XP blending.

### Multi-Device Sync

Because analytics are stored in Matrix rooms, they sync across devices automatically via the Matrix sync protocol. On login or language change, [`AnalyticsSyncController`](lib/pangea/analytics_data/analytics_sync_controller.dart) performs a bulk catch-up from the analytics room before starting real-time tracking.

## Celebration Moments

[`AnalyticsUpdateDispatcher`](lib/pangea/analytics_data/analytics_update_dispatcher.dart) emits [typed events](lib/pangea/analytics_data/analytics_update_events.dart) that the UI listens for to trigger celebratory animations:

| Event | UX Response |
|-------|-------------|
| [`XPGainedEvent`](lib/pangea/analytics_data/analytics_update_events.dart) | Floating "+N" animation anchored to the word the user interacted with |
| [`ConstructLevelUpEvent`](lib/pangea/analytics_data/analytics_update_events.dart) | Growth animation on the word's token in the toolbar |
| [`LevelUpEvent`](lib/pangea/analytics_data/analytics_update_events.dart) | Full-screen banner + chime + AI-generated learning summary |
| [`MorphUnlockedEvent`](lib/pangea/analytics_data/analytics_update_events.dart) | Notification that a new grammar pattern has been discovered |
| [`NewConstructsEvent`](lib/pangea/analytics_data/analytics_update_events.dart) | Subtle highlight (first-ever interaction with a word) |

These events are always anchored to a specific UI element (via a `targetID`) so the animation appears in context, not as a disconnected popup. Use the [`AnalyticsUpdater`](lib/pangea/analytics_data/analytics_updater_mixin.dart) mixin on any widget that triggers analytics and wants to show immediate XP/growth feedback.

## Analytics for Teachers (Space Analytics)

Teachers/space admins can view aggregate analytics for their students:
- Download summaries per student or per space
- See inactive student indicators
- Request detailed analytics reports

This data flows from each student's analytics room to the teacher view — the teacher never sees raw construct data, only aggregated summaries.

## Key Contracts

- **Never fetch analytics from Synapse per-message.** The local database is the runtime source of truth.
- **XP per construct caps at the flower threshold (100).** [`ConstructUses.cappedUses`](lib/pangea/analytics_misc/construct_use_model.dart) enforces this, preventing level inflation from repeatedly encountering familiar words.
- **Level can never visibly decrease** from user-initiated actions (blocking, language switching). Use offsets to maintain.
- **The "other" category is always filtered out** of aggregations and displays. It represents unclassifiable tokens.
- **Analytics initialization must complete before any UI reads.** All public methods await an init completer.
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

