---
applyTo: "lib/pangea/practice_activities/**,lib/pangea/analytics_practice/**,lib/pangea/toolbar/message_practice/**"
---

# Practice Exercises

Practice exercises are multiple-choice exercises that reinforce vocabulary and grammar from real conversations. There are no disconnected flashcard decks — every practice item traces back to a message the user sent or received.

For **conversation activities**, see [conversation-activities.instructions.md](conversation-activities.instructions.md).

## Three Entry Points

| Entry Point | What It Is | Where It Lives | Activity Types Used |
|---|---|---|---|
| **Vocab Practice** | Standalone session of ~10 vocab exercises drawn from the user's weakest words | Analytics page → "Practice Vocab" button → [`AnalyticsPractice(type: vocab)`](../../lib/pangea/analytics_practice/analytics_practice_page.dart) | `lemmaMeaning`, `lemmaAudio` |
| **Grammar Practice** | Standalone session of ~10 grammar exercises drawn from recent errors + weak morphology | Analytics page → "Practice Grammar" button → [`AnalyticsPractice(type: morph)`](../../lib/pangea/analytics_practice/analytics_practice_page.dart) | `grammarError`, `grammarCategory` |
| **Message Practice** | Per-message practice accessed from the toolbar; exercises target words in that specific message | Toolbar → 💪 button → [`PracticeController`](../../lib/pangea/toolbar/message_practice/practice_controller.dart) | `wordMeaning`, `wordFocusListening`, `emoji`, `morphId` |

All three entry points produce the same [`ConstructUseModel`](../../lib/pangea/analytics_misc/constructs_model.dart) records, so practice from any source contributes equally to the user's vocabulary garden and XP.

---

## Design Goals

1. **Spaced repetition without the UI**: Users never configure schedules. The system silently prioritizes words they haven't seen recently and content words over function words.
2. **Multi-modal learning**: Each word can be practiced through listening, meaning, emoji association, and grammar analysis — hitting visual, auditory, and semantic learning channels.
3. **Completion, not perfection**: Wrong answers still contribute (at reduced XP), keeping the experience encouraging.
4. **Always from real messages**: Every practice target traces back to a token from a real conversation message.

---

## Target Prioritization: Which Words First?

All practice paths aim to surface words/constructs the user hasn't practiced recently, but they currently use **two separate implementations** rather than a shared service.

### Message Practice — scoring formula

[`PracticeSelectionRepo._fetchPriorityScores`](../../lib/pangea/practice_activities/practice_selection_repo.dart) computes a numeric score per token:

```
score = daysSinceLastUsed × (isContentWord ? 10 : 7)
```

- **`daysSinceLastUsed`**: looked up via `getConstructUses` → `lastUseByTypes` filtered to the specific activity type's associated construct-use types. If the word has never been practiced, defaults to **20 days**.
- **Content word bonus**: nouns, verbs, and adjectives get a 10× multiplier; function words (articles, prepositions) get 7×. This meaningfully favors content words when recency is equal.
- Tokens are sorted by score descending, top 8 taken, then shuffled.

### Standalone Practice — simple recency sort

[`AnalyticsPracticeSessionRepo._fetchVocab`](../../lib/pangea/analytics_practice/analytics_practice_session_repo.dart) and `_fetchAudio` sort by `lastUsed` ascending with nulls first (never-practiced words come first). There is **no scoring formula** and **no content-word bonus**.

Grammar targets use a different strategy:
- **`_fetchErrors`**: selects recent grammar mistakes, skipping any construct practiced in the last 24 hours.
- **`_fetchMorphs`**: sorts morph constructs by `lastUsed` ascending (same as vocab).

### ⚠️ Divergence note

These two systems evolved independently. The message-practice scorer is more nuanced (explicit formula, content-word weighting, per-activity-type recency). The standalone path is simpler but misses the content-word boost and uses aggregate recency rather than per-type recency. Unifying them into a shared prioritization service is a natural improvement — see Future Work.

### 🧠 Design Direction: Use-Type-Aware Spaced Repetition

The current scoring only considers **recency** and **content-word status**. It ignores the rich signal from [`ConstructUseTypeEnum`](../../lib/pangea/analytics_misc/construct_use_type_enum.dart) — specifically **how** the user encountered or practiced each word. The next evolution should classify words into priority tiers based on their use-type history:

**Three-tier model:**

| Tier | Who goes here | Practice priority |
|---|---|---|
| **Suppressed** | Lemmas whose most recent chat use is `wa` (without assistance) AND no subsequent incorrect practice | **0** — skip entirely |
| **Active** | Lemmas encountered through `ta` (IT) or `ga` (IGC), OR lemmas with a recent incorrect practice answer (`incXX`) | **High** — prioritize these |
| **Maintenance** | Everything else — correctly practiced but aging | **Normal** — standard recency-based |

**Tier transitions:**
- A `wa` use → moves to Suppressed (user knows this word)
- A `ta` or `ga` use → moves to Active (user needed help)
- An incorrect practice answer → moves to Active (user struggled)
- N consecutive correct practice answers → Active → Maintenance (learning is sticking)
- Time passes without interaction → Maintenance words naturally bubble up via recency

**Within each tier**, the existing scoring formula applies: `daysSinceLastUsed × (isContentWord ? 10 : 7)`. Active-tier words get an additional multiplier (e.g., ×2) so they always appear before maintenance words of similar age.

**Key principle**: Words used through IT and IGC should be practiced **much more** than `wa` words. A `wa` word should only re-enter practice if the user later gets it wrong.

**Example scenario:**
1. User types "gato" correctly without assistance → `wa` → Suppressed. Won't appear in practice.
2. User uses IT to translate "mariposa" → `ta` → Active. High priority for practice.
3. User practices "mariposa" and gets it wrong → `incLM` → stays Active, priority boosted.
4. User practices "mariposa" correctly 3 times → Active → Maintenance.
5. Two weeks pass with no interaction → Maintenance, but high recency score → likely to appear.
6. User later misspells "gato" and IGC corrects it → `ga` → moves from Suppressed back to Active.

### ⚠️ Grammar Error Practice: Missing Message Data

[`_fetchErrors`](../../lib/pangea/analytics_practice/analytics_practice_session_repo.dart) finds grammar practice material by querying construct uses of type `ga` (grammar accepted), then resolving the original message via `room?.getEventById(eventID)`. While the Matrix SDK's `Room.getEventById` already falls back to a server fetch if the event isn't in the local database, the chain can still fail at an earlier step: `client.getRoomById(roomID)` returns null if the room isn't loaded in memory (e.g., the user left). When the event *is* found, additional data is needed — the `PangeaMessageEvent` wrapper requires a timeline, tokens, choreo data, and translations, all of which are only available if the full message representation events are also accessible. A similar pattern applies to `_fetchAudio` and `_fetchMorphs`, which need example messages with token data and audio. See Future Work for improvements.

---

## Activity Types

The [`ActivityTypeEnum`](../../lib/pangea/practice_activities/activity_type_enum.dart) defines all exercise types. They split into two groups:

### Message Practice Types (toolbar)

| Type | Enum Value | What the User Does | Learning Channel |
|---|---|---|---|
| Listening | `wordFocusListening` | Hears the word spoken, taps the correct token in the message | Auditory recognition |
| Meaning | `wordMeaning` | Sees L1 translations, picks the right one for a highlighted word | Semantic retrieval |
| Emoji | `emoji` | Chooses the best emoji for a word (associative learning) | Visual association |
| Grammar | `morphId` | Matches morphological features (tense, number, case) to values | Analytical/structural |

### Standalone Practice Types (analytics page)

| Type | Enum Value | What the User Does | Generator |
|---|---|---|---|
| Vocab Meaning | `lemmaMeaning` | Picks the correct lemma definition from distractors | [`VocabMeaningActivityGenerator`](../../lib/pangea/analytics_practice/vocab_meaning_activity_generator.dart) |
| Vocab Audio | `lemmaAudio` | Hears a word in the context of an example sentence, identifies it | [`VocabAudioActivityGenerator`](../../lib/pangea/analytics_practice/vocab_audio_activity_generator.dart) |
| Grammar Category | `grammarCategory` | Identifies the correct morph tag (e.g., "Past Tense") for a word | [`MorphCategoryActivityGenerator`](../../lib/pangea/analytics_practice/morph_category_activity_generator.dart) |
| Grammar Error | `grammarError` | Picks the correct replacement for a grammar error they made | [`GrammarErrorPracticeGenerator`](../../lib/pangea/analytics_practice/grammar_error_practice_generator.dart) |

Each activity type maps to specific [`ConstructUseTypeEnum`](../../lib/pangea/analytics_misc/construct_use_type_enum.dart) values for correct/incorrect/ignored answers (e.g., `corLM`/`incLM` for lemmaMeaning).

---

## Standalone Practice Sessions (Vocab & Grammar)

### Session Lifecycle

1. [`AnalyticsPracticeSessionRepo.get(type, language)`](../../lib/pangea/analytics_practice/analytics_practice_session_repo.dart) builds a session:
   - **Vocab**: fetches the user's weakest lemmas (by spaced-repetition score), splits ~50/50 between `lemmaAudio` (needs example messages with audio) and `lemmaMeaning` targets
   - **Grammar**: fetches recent grammar errors first (`grammarError` targets), then fills remaining slots with weak morph features (`grammarCategory` targets)
   - Session size: 10 exercises + 5 error buffer (constants in [`AnalyticsPracticeConstants`](../../lib/pangea/analytics_practice/analytics_practice_constants.dart))
2. [`AnalyticsPracticeState`](../../lib/pangea/analytics_practice/analytics_practice_page.dart) manages the session UI — progress bar, timer, activity queue, hints
3. For each target, a [`MessageActivityRequest`](../../lib/pangea/practice_activities/message_activity_request.dart) is sent to the appropriate generator
4. The generator returns a [`PracticeActivityModel`](../../lib/pangea/practice_activities/practice_activity_model.dart) subclass with choices and answers
5. On answer, a construct use is recorded and the session advances

### Session Completion

When all targets are answered, [`CompletedActivitySessionView`](../../lib/pangea/analytics_practice/completed_activity_session_view.dart) shows:
- Total correct / incorrect / skipped
- Time elapsed (with bonus XP if under 60 seconds)
- Per-item review

### Subscription Gate

Standalone practice requires an active subscription. [`UnsubscribedPracticePage`](../../lib/pangea/analytics_practice/unsubscribed_practice_page.dart) is shown if the user isn't subscribed.

---

## Message Practice (Toolbar)

### Target Selection

[`PracticeSelectionRepo`](../../lib/pangea/practice_activities/practice_selection_repo.dart) determines which tokens in a message become practice targets:

- Only tokens with `saveVocab = true` on their lemma (filters out punctuation, numbers, etc.)
- Only messages in the user's target language (L2)
- Deduplicated by lemma — if "running" and "runs" appear in the same message, only one is selected
- Capped at 5 targets per activity type per message (avoids overwhelming long messages)

Selections are cached per message with a 1-day TTL in [`PracticeSelection`](../../lib/pangea/practice_activities/practice_selection.dart).

Token priority within each message uses the scoring formula described in [Target Prioritization](#target-prioritization-which-words-first) above.

### Practice Modes

[`MessagePracticeMode`](../../lib/pangea/toolbar/message_practice/message_practice_mode_enum.dart) defines the four toolbar modes: `listening`, `wordMeaning`, `wordEmoji`, `wordMorph`. Each mode maps to an `ActivityTypeEnum` and shows per-word buttons on the message. When all words in a mode are complete, the mode's icon turns gold.

### Controller

[`PracticeController`](../../lib/pangea/toolbar/message_practice/practice_controller.dart) manages per-message practice state:
- Fetches `PracticeSelection` on construction
- Generates activities on demand via [`PracticeRepo`](../../lib/pangea/practice_activities/practice_generation_repo.dart)
- Records answers via [`PracticeRecordController`](../../lib/pangea/toolbar/message_practice/practice_record_controller.dart)
- Plays TTS on correct answers for audio reinforcement

---

## Activity Generation

[`PracticeRepo`](../../lib/pangea/practice_activities/practice_generation_repo.dart) is the central dispatch for generating exercises. It:

1. Receives a `MessageActivityRequest` with a `PracticeTarget` (tokens + activity type + optional morph feature)
2. Routes to the correct generator based on activity type
3. Caches results per-target with a 1-day TTL to avoid re-generating on re-render
4. Message-practice types (`wordMeaning`, `emoji`, `morphId`, `wordFocusListening`) call the choreographer API
5. Standalone types (`lemmaMeaning`, `lemmaAudio`, `grammarCategory`, `grammarError`) generate locally using lemma data and morph mappings

### Model Hierarchy

[`PracticeActivityModel`](../../lib/pangea/practice_activities/practice_activity_model.dart) is a sealed class with subclasses for each activity type:
- `VocabMeaningPracticeActivityModel`, `VocabAudioPracticeActivityModel`
- `MorphCategoryPracticeActivityModel`, `GrammarErrorPracticeActivityModel`
- `LemmaPracticeActivityModel`, `LemmaMeaningPracticeActivityModel`
- `EmojiPracticeActivityModel`, `MorphMatchPracticeActivityModel`
- `WordListeningPracticeActivityModel`

All expose a `multipleChoiceContent` (choices + answers) and produce a `PracticeTarget` for recording.

---

## Key Contracts

- **Practice targets are deterministic per message.** For a given eventId + language + token set, the same targets are generated and cached. Don't introduce randomness that would change targets on re-render.
- **Practice never blocks on network.** Selection happens locally from cached token data. Activity content fetches from choreo, but the UI shows shimmer placeholders, never a blocking spinner.
- **Emoji and meaning choices persist beyond the practice session.** They become the user's personal annotation on that lemma, visible in word cards and analytics.
- **All practice produces construct uses.** Whether from the toolbar or the standalone page, every answer is recorded as a `ConstructUseModel` that feeds into the analytics system.

## Future Work
*Last updated: 2026-02-15*

**Practice Types & Modalities**

- [pangeachat/client#5656](https://github.com/pangeachat/client/issues/5656) — Voice practice ideas
- [pangeachat/client#3175](https://github.com/pangeachat/client/discussions/3175) — Speaking practice for Voice/Audio message
- [pangeachat/client#3176](https://github.com/pangeachat/client/discussions/3176) — New type of practice activity
- [pangeachat/client#2678](https://github.com/pangeachat/client/discussions/2678) — Listening exercises
- [pangeachat/client#5654](https://github.com/pangeachat/client/issues/5654) — Are there more places where it makes sense to use the word audio?

**Practice Generation & Targeting**

- [pangeachat/client#5700](https://github.com/pangeachat/client/issues/5700) — Unified practice target selection with use-type-aware spaced repetition and server-side message fetch (covers Parts 1 & 2: shared scorer + three-tier model)
- [pangeachat/client#2677](https://github.com/pangeachat/client/discussions/2677) — Generate activities based on stored word forms from analytics
- [pangeachat/2-step-choreographer#1546](https://github.com/pangeachat/2-step-choreographer/issues/1546) — Add emojis to distractor generation

**Practice UX & Feedback**

- [pangeachat/client#5436](https://github.com/pangeachat/client/discussions/5436) — If messages practice is complete, put special gold barbell reaction on it
- Persist a completion record to the Matrix room when a user completes all 4 practice modes on a message, making practice targets deterministic across sessions and devices
- [pangeachat/client#3569](https://github.com/pangeachat/client/discussions/3569) — Practice Exercises in the analytics page

**Bugs & Quality**

- [pangeachat/2-step-choreographer#1568](https://github.com/pangeachat/2-step-choreographer/issues/1568) — Vocab Practice in English instead of L1

**Server-Side & Cross-Device**

- Server-side practice history to enable cross-device spaced repetition
- [pangeachat/client#5700](https://github.com/pangeachat/client/issues/5700) Part 3 — Server-side message fetch fallback for practice (room resolution, related sub-event data)
- More activity types (fill-in-the-blank, sentence reordering, pronunciation scoring)
