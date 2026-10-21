---
applyTo: "lib/routes/chat/toolbar/practice_exercises/**,lib/routes/chat/toolbar/message_practice/**,lib/routes/analytics/construct_analytics/practice/**"
---

# Practice Exercises

Practice exercises are short solo exercises that reinforce vocabulary and grammar from real conversations: multiple-choice items, and a read-aloud item for speaking. There are no disconnected flashcard decks — every practice item traces back to a message the user sent or received.

For **conversation activities**, see [activities.instructions.md](activities.instructions.md).

## Terminology

| Term | Meaning | Code modules |
|---|---|---|
| **Practice exercise** | Multiple-choice quiz, or a read-aloud item, reinforcing vocab/grammar from real messages (solo) | `practice_activities/` (legacy name), `analytics_practice/`, `toolbar/message_practice/` |

## Four Entry Points

| Entry Point | What It Is | Where It Lives | Activity Types Used |
|---|---|---|---|
| **Vocab Practice** | Standalone session of ~10 vocab exercises drawn from the user's weakest words | Analytics page → "Practice Vocab" button, or the connection banner's "Practice vocab while you wait" → [`AnalyticsPracticePage`](../../lib/routes/analytics/construct_analytics/practice/analytics_practice_page.dart) (`type: vocab`) | `lemmaMeaning`, `lemmaAudio`, `readAloud` (`lemmaMeaning` only [offline](#offline-practice)) |
| **Grammar Practice** | Standalone session of ~10 grammar exercises drawn from recent errors + weak morphology | Analytics page → "Practice Grammar" button → [`AnalyticsPracticePage`](../../lib/routes/analytics/construct_analytics/practice/analytics_practice_page.dart) (`type: morph`) | `grammarError`, `grammarCategory` (both [offline](#offline-practice), `grammarError` without its hint) |
| **Objective Practice** | A vocab session scoped to one Mission's target vocabulary (see [Objective practice](#objective-practice)) | The Mission card's Practice button and the Practice button on a Learning Objective's page → the same page with `practice:vocab/<missionId>` in the URL | `lemmaMeaning`, `lemmaAudio`, `readAloud` |
| **Message Practice** | Per-message practice accessed from the toolbar; exercises target words in that specific message | Toolbar → 💪 button → [`PracticeController`](../../lib/routes/chat/toolbar/message_practice/practice_controller.dart) | `wordMeaning`, `wordFocusListening`, `emoji`, `morphId` |

All four entry points produce the same [`ConstructUseModel`](../../lib/pangea/analytics_misc/constructs_model.dart) records, so practice from any source contributes equally to the user's vocabulary garden and XP.

### Objective practice

A Mission's Practice control ([client#9438](https://github.com/pangeachat/client/issues/9438)) starts a vocab session drawn only from the Mission's **target vocabulary** — every suggested-vocab entry across the activities that satisfy it, once per lemma (`QuestObjectiveGroup.vocab`), read from the first joined course that carries the Mission as that course shows it (its copy, else its pins). Selection takes the learner's own constructs for those words first, through the usual audio and meaning generators, then adds a **meaning exercise built straight from the plan's lemma and part of speech** for each word the learner has never used, so a Mission's words can be practised before they have come up in a conversation. Set phrases are skipped there, since the meaning generator's distractors are per lemma. A Mission with no joined course behind it (a stale link, a course since left) falls back to the learner's usual session.

The scope rides the URL token so it survives a panel swap and can be linked to, and it is part of the session's identity: a tap for the same Mission resumes the live session, a tap for another Mission or an unscoped Practice button replaces it after the usual confirmation. The panel names the Mission under its title. A Mission-scoped session is analytics-page practice: its uses name no room, so its XP counts toward every Mission whose word list holds the drilled word, whether or not the learner has used it before — a correct answer on a new word adds it to their vocabulary, earns its XP and counts toward the Mission at once. The rule is the resolver's: [quests.instructions.md](quests.instructions.md), "What fills a Mission".

---

## Design Goals

1. **Spaced repetition without the UI**: Users never configure schedules. The system silently prioritizes words they haven't seen recently and content words over function words.
2. **Multi-modal learning**: Each word can be practiced through listening, speaking, meaning, emoji association, and grammar analysis — hitting visual, auditory, semantic and spoken learning channels.
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

### Standalone Practice — practice sorting

Each standable practice type has its own practice target generator.

| Type | Generator |
| --- | --- |
| PracticeExerciseTypeEnum.grammarCategory | [GrammarMatchTargetGenerator](../../lib/routes/analytics/construct_analytics/practice/grammar_match_target_generator.dart) |
| PracticeExerciseTypeEnum.grammarError | [GrammarErrorTargetGenerator](../../lib/routes/analytics/construct_analytics/practice/grammar_error_target_generator.dart) |
| PracticeExerciseTypeEnum.lemmaAudio | [VocabAudioTargetGenerator](../../lib/routes/analytics/construct_analytics/practice/vocab_audio_target_generator.dart) |
| PracticeExerciseTypeEnum.lemmaMeaning | [VocabMeaningTargetGenerator](../../lib/routes/analytics/construct_analytics/practice/vocab_meaning_target_generator.dart) |

Each of these is passed a full list of the user's construct data for the relevant type (vocab or grammar) and uses [practiceSort](../../lib/routes/analytics/construct_analytics/practice/construct_practice_extension.dart) to order them by relevance for the given type.  

[GrammarErrorTargetGenerator](../../lib/routes/analytics/construct_analytics/practice/grammar_error_target_generator.dart) acts differently. Because constructs from grammar error practice exercises have an eventID attached, these eventIDs are used to filter out constructs from events that happened in the last 24 hours to prevent users from [getting exercies for the same messages too many times in a row.](https://github.com/pangeachat/client/issues/7360)

### ⚠️ Divergence note

These two systems evolved independently. The message-practice scorer is more nuanced (explicit formula, content-word weighting, per-activity-type recency). The standalone path is simpler but misses the content-word boost and uses aggregate recency rather than per-type recency. Unifying them into a shared prioritization service is a natural improvement — see Future Work.

### 🧠 Design Direction: Use-Type-Aware Spaced Repetition

The current scoring only considers **recency** and **content-word status**. It ignores the rich signal from [`ConstructUseTypeEnum`](../../lib/pangea/analytics_misc/construct_use_type_enum.dart) — specifically **how** the user encountered or practiced each word. The next evolution should classify words into priority tiers based on their use-type history:

**Three-tier model:**

| Tier | Who goes here | Practice priority |
|---|---|---|
| **Suppressed** | Lemmas whose most recent chat use is `wa` (writing assistance ran, message correct) or `unk` (no writing assistance run) AND no subsequent incorrect practice | **0** — skip entirely |
| **Active** | Lemmas encountered through `ta` (interactive translation) or `ga` (grammar correction / IGC), OR lemmas with a recent incorrect practice answer (`incXX`) | **High** — prioritize these |
| **Maintenance** | Everything else — correctly practiced but aging | **Normal** — standard recency-based |

**Tier transitions:**
- A `wa` or `unk` use → moves to Suppressed (user produced the word correctly, no help needed)
- A `ta` or `ga` use → moves to Active (user needed help)
- An incorrect practice answer → moves to Active (user struggled)
- N consecutive correct practice answers → Active → Maintenance (learning is sticking)
- Time passes without interaction → Maintenance words naturally bubble up via recency

**Within each tier**, the existing scoring formula applies: `daysSinceLastUsed × (isContentWord ? 10 : 7)`. Active-tier words get an additional multiplier (e.g., ×2) so they always appear before maintenance words of similar age.

**Key principle**: Words the user needed help with (interactive translation or grammar correction) should be practiced **much more** than words they already produce correctly (`wa`/`unk`). Such a word should only re-enter practice if the user later gets it wrong.

**Example scenario:**
1. User types "gato" correctly with no correction needed → `unk` (or `wa` if writing assistance ran and passed) → Suppressed. Won't appear in practice.
2. User uses IT to translate "mariposa" → `ta` → Active. High priority for practice.
3. User practices "mariposa" and gets it wrong → `incLM` → stays Active, priority boosted.
4. User practices "mariposa" correctly 3 times → Active → Maintenance.
5. Two weeks pass with no interaction → Maintenance, but high recency score → likely to appear.
6. User later misspells "gato" and it's corrected during grammar checking → `ga` → moves from Suppressed back to Active.

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
| Read Aloud | `readAloud` | Reads the example sentence aloud; correct when the target word is heard (see [Speaking practice](#speaking-practice)) | `ReadAloudPracticeExerciseGenerator` |

Each activity type maps to specific [`ConstructUseTypeEnum`](../../lib/pangea/analytics_misc/construct_use_type_enum.dart) values for correct/incorrect/ignored answers (e.g., `corLM`/`incLM` for lemmaMeaning).

---

## Standalone Practice Sessions (Vocab & Grammar)

### Session Lifecycle

1. [`AnalyticsPracticeSessionRepo.get(type, userL1, userL2)`](../../lib/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart) selects the session's targets (words/constructs + exercise type), NOT their content:
   - **Vocab**: picks the user's weakest lemmas (by spaced-repetition score) and splits them among `lemmaMeaning`, `lemmaAudio` and `readAloud` targets, about a third each. The split is by **count**; audio and read-aloud candidates are picked by a cheap local check that the lemma has an example-bearing use, and the example message itself is resolved later at generation (see [Loading & Generation Sequencing](#loading--generation-sequencing)). Listening and read-aloud take turns down the one priority order of those words, listening first, so a small example-bearing pool is shared rather than spent on listening before read-aloud gets any. A third each keeps speaking in every session without letting an item that needs a microphone and the network dominate it.
   - **Grammar**: picks recent grammar errors first (`grammarError` targets), then fills remaining slots with weak morph features (`grammarCategory` targets)
   - Session size: 10 exercises shown, plus a 5-item error buffer (15 targets generated — `targetsToGenerate`; constants in [`AnalyticsPracticeConstants`](../../lib/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart)). The "~10" entry-point sessions above are this same 10 shown.
2. [`PracticeSessionController`](../../lib/routes/analytics/construct_analytics/practice/analytics_practice_session_controller.dart) owns the session and the exercise queue; the page widgets show progress bar, timer, hints.
3. For each target, a [`MessagePracticeExerciseRequest`](../../lib/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart) is routed by [`PracticeRepo`](../../lib/routes/chat/toolbar/practice_exercises/practice_generation_repo.dart) to the appropriate generator.
4. The generator returns a [`PracticeExerciseModel`](../../lib/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart) subclass with choices and answers.
5. On answer, a construct use is recorded and the session advances.

### Session Completion

When all targets are answered, [`CompletedActivitySessionView`](../../lib/pangea/analytics_practice/completed_activity_session_view.dart) shows:
- Total correct / incorrect / skipped
- Time elapsed (with bonus XP if under 60 seconds)
- Per-item review

### Loading & Generation Sequencing

Standalone practice loads in two phases, and the learner waits behind a spinner for both:

1. **Selection** ([`AnalyticsPracticeSessionRepo.get`](../../lib/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart)) picks the session's targets from aggregated constructs (local analytics).
2. **Content generation** ([`PracticeSessionController.getNextExercise`](../../lib/routes/analytics/construct_analytics/practice/analytics_practice_session_controller.dart)) turns targets into exercises. The **first** exercise is awaited and shown; the moment it resolves, generation of **every** remaining exercise is kicked off eagerly and concurrently (`_fillExerciseQueue`), so later exercises are prefetched and waiting by the time the learner reaches them.

**The session clock's zero is the first exercise appearing, not the end of selection.** Neither loading phase is on the learner's clock: the timer reads a frozen `00:00` throughout, and the cluster badge only appears once there is a clock to show. Generation is a network call whose length the learner does not control, and elapsed time buys a speed bonus — charging them for the wait would spend part of that bonus before they can answer anything (#8966).

Selection must stay cheap: it reads aggregated constructs from local analytics and does **not** resolve per-target example messages, audio, or Matrix events. Those resolve during content generation, inside the eager background queue. The goal is not to defer the work — every exercise is still prefetched — but to keep it from gating first paint: resolving example messages *during selection* blocked the first exercise on N serial event fetches, which made practice load slowly and inconsistently (#7702).

A `lemmaAudio` target whose audio example can't be resolved at generation **falls back to a `lemmaMeaning` exercise for the same lemma**, so a deferred resolution failure never leaves a gap. This is a degradation path only — the audio/meaning mix is set at selection by count, so it doesn't materially shift the mix.

A `readAloud` target falls back the same way — to a `lemmaMeaning` exercise for the same lemma — when its example message can't be resolved, when the microphone is refused or absent, or when no transcription route is available. A refusal is remembered for the session, so later read-aloud items fall back without asking again.

### Session Persistence & Lifecycle

A standalone practice session is a **background activity that outlives its
panel** (the routing-level rules — silent leave, explicit end, the cluster
badge, and the same-section analytics block — live in
[routing.instructions.md](routing.instructions.md#practice-is-a-persistent-background-session)):

- **The session lives in a holder that survives panel teardown.** Closing the
  practice panel (or navigating anywhere else) neither disposes nor pauses the
  session; re-opening practice re-attaches to the held session and resumes at
  the current exercise. The holder is in-memory only — a refresh or app
  restart starts fresh.
- **One session at a time**, across vocab and grammar. Starting a new session
  while an unfinished one is held confirms first, then replaces it.
- **A session ends five ways**: finishing all exercises (completion view,
  XP awarded), the explicit **End session** control (confirms, discards
  progress), being replaced by a newly started session (confirms), by automatically closing after [AnalyticsPracticeConstants.idleTimeout](../../lib/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart) inactivity, or by the account logging out — a session belongs to one learner and never carries into the next account. Ending
  clears the holder and the cluster badge.
- **Elapsed time is wall-clock from the first exercise appearing** (see [Loading & Generation Sequencing](#loading--generation-sequencing)), not time-on-screen. The timer keeps counting while the panel is closed — an anti-cheat mechanism in its own right: leaving mid-session to consult a dictionary or an AI costs the clock, so the speed bonus rewards finishing unaided in one sitting. The cluster badge shows the same running clock.

### Offline Practice

A practice session that starts while the app cannot reach Pangea ([connection-status](connection-status.instructions.md)) is an **offline session**, whichever button started it. It uses only what the device already has, and it has as many exercises as that allows, up to the usual 10. When the device has nothing to practice, the page says "Not enough is saved on this device to practice offline. Try again when you're back online."

**Vocab.**

- It uses meaning exercises only, because audio exercises need an example message and speech audio from the network, and read-aloud exercises need transcription from it.
- Every word in it, the answers and the wrong choices alike, has a meaning saved on the device. That is the meaning the learner picked in meaning practice, or a dictionary meaning the app fetched in the last 30 days, from a word card or from practice ([`ConstructIdentifier.knownMeanings`](../../lib/features/analytics/construct_identifier.dart)).
- Words come in the usual priority order, without the 24-hour pause on recently practiced words, because the saved words are all the session has.
- The pronunciation line under the word is hidden, because it needs the network. The example message shows only when that message is saved on the device.

**Grammar.**

- It uses both grammar exercises, built only from messages saved on the device. The app does not ask the server for a message that is not saved, because that request can wait 35 seconds when the server is not answering.
- Grammar-category exercises need grammar labels for this language pair saved on the device, of any age ([grammar-analytics](grammar-analytics.instructions.md#morph-feature-inventory)). Without them, the session uses grammar-error exercises only, because the built-in labels are in English.
- Grammar-error exercises have no hint, because the hint is the sentence's translation, which needs the network. The learner's own error is always one of the choices.
- The 24-hour pauses on recently practiced grammar and sentences still apply.

Answers are recorded and earn XP as usual. They stay on the device and upload when the connection returns ([analytics-system § Local-First, Sync-Later](analytics-system.instructions.md#local-first-sync-later)).

A session keeps the mode it started in. While the app cannot reach Pangea, the practice page says "Offline. Your answers upload when you're back." under the progress bar. The completion view says "Saved on this device. Your XP uploads when you're back online."

### Subscription Gate

Standalone practice requires an active subscription. [`UnsubscribedPracticePage`](../../lib/routes/analytics/construct_analytics/practice/unsubscribed_practice_page.dart) is shown if the user isn't subscribed.

### Speaking practice

Speaking practice is not a session of its own: it is the **read-aloud exercise**, mixed into every vocab session beside meaning and listening ([client#8967](https://github.com/pangeachat/client/issues/8967)). The learner reads a sentence they met in a real chat aloud, and the app shows which words it heard. Playtesters asked to practise speaking on sentences of their choosing rather than by inventing a reply to the bot in a voice message, and the live transcription voice messages use lets the words settle under their voice. It is mixed in rather than given a button of its own so that speaking lives inside the one practice habit the app already has: a learner meets it without opting in, and every vocab entry point — the analytics page, a Mission's Practice, the Learning Objectives page — carries it with no new surface. Like the rest of a vocab session it names no room, so its XP counts toward every Mission whose word list holds the word.

**An item** is the sentence of the weak word's example message that holds the target, whole. A sentence longer than eight words is cut to a window of eight around the target inside it, with an ellipsis on each cut side, since a long sentence is a chore to read aloud and the target is the point; a cut at a stop reads naturally where one in the middle of a clause did not. The target is bold, with its pronunciation line and the emoji and meaning the learner has given it, over a player for the reference audio and the mic. The item looks like the other two exercises: the sentence in the theme-coloured bubble the listening answer uses, players the column's full width like the listening player, and Skip and Continue at the foot of the page where the listening exercise keeps its Continue, outside the scrolling content. The flow is the one the design team drew ([Figma](https://www.figma.com/design/JLTmfC5gKrFkBCylEUTaLf/In-chat-functionality?node-id=4309-13832)): listen, record, compare.

- **Hear it first** is a toggle in the Audio section of learning settings, beside the other audio switches, off by default. On, the reference audio plays when the item appears and the mic pulses once it ends; off, the item opens on the mic, and the play button is still there. Off by default so the learner tries the sentence before hearing it and reaches for the example when they need the help, which is what a playtester asked for after a round (2026-10-20); on is there for the listen-then-repeat loop teachers asked for ([#2961](https://github.com/pangeachat/client/issues/2961)), and for a learner who would otherwise guess at a sentence they cannot yet read. The switch governs the read-aloud item alone; no other audio surface reads it. The reference is the sentence as shown, read by the generated voice and cached per sentence the way every generated audio is, and hearing it is listening exposure, recorded as such ([analytics-system](analytics-system.instructions.md#listening-exposure)). The listening exercise's message audio is not reused: it reads the whole message, and a trimmed example would not match what is on screen.
- **Recording** starts on a tap, never on its own. The mic says what it is doing: *getting ready* from the tap until the microphone is live (permission asked, and the relay opened where the language streams), then *listening*; nothing is recorded before it says so, so a learner who starts reading on the tap is told to wait rather than cut off. As the learner reads, the live transcript shows under the sentence as it settles, as it does while recording a voice message, and each reference word fills in as the transcript settles it, in order, so the sentence completes under their voice; a settled word changes weight as well as colour, and the mic's accessible name says how many words are still unheard, so colour is never the only carrier. Recording ends on a second tap, when every word has settled, or at the voice message's maximum length; **Start over**, under the mic while recording, discards the recording in progress and begins a fresh one without spending a take. The reference and the mic never run together: the mic opens only once playback ends, and a tap on the mic during playback stops the playback first.
- **Compare.** When the recording ends, the item shows the reference player over every take the learner has made, up to the three allowed, each with the volume bars every recording in the app shows and the transcript heard from it, so the shapes compare as well as the sounds and a retry can be set against the take before it. A retry keeps the last take's marks: the words it missed stay marked while the next take is recorded, until that take settles them, so the learner knows what to fix; a playtester lost the previous take and its misses on the mic tap and could not tell what to improve (2026-10-21). The learner's recordings stay on the device for the item and go nowhere but to transcription.
- **What counts.** The item is correct when the target word was heard; the other words are feedback only. The target alone earns the use, as in every other exercise, so a long sentence is worth no more than a short one.
- **Not heard is a retry, not a wrong answer.** A missed word is as likely the recognizer's miss as the learner's: recognition pinned to the target language is forgiving by design and reports whether a word was intelligible, not whether it sounded native. A word counts as heard whatever its case or vowel accents, since a recognizer drops a stress mark as readily as it writes one. A miss leaves the missed words unfilled and offers another go, three recordings per item: enough to fix a slip, few enough that a word the recognizer will never hear does not trap the learner. The item is recorded once, correct on the first full pass or incorrect when the tries run out. **Skip** sits beside Continue the whole time, not only after a failure, since a learner may be somewhere they cannot speak or the recognizer may not be taking their recording; it records only the usual skip, so the word is not chosen again soon. The copy says what was heard, never that a word was pronounced well or badly, and there is no score: the filled sentence is the feedback.

**Transcription.** An item uses the live streaming route voice messages use ([streaming-stt](../../../2-step-choreographer/.github/instructions/streaming-stt.instructions.md)) wherever the learner's target language is routed for streaming, and the judge is the settled final. Where the language is not routed, the recorder's batch path runs instead and the words fill in together after the recording ends. The recording is not sent through the batch route as well: a known reference makes the match far easier than open transcription, and a second transcription per item would double the cost. On both routes the sentence goes along as the expected-text hint ([speech-to-text](../../../2-step-choreographer/.github/instructions/speech-to-text.instructions.md#expected-text-hint)), so recognition is biased toward what the learner was asked to read: a fair attempt comes back matching, which is the point; the same bias can turn a real slip into the expected word, which is one more reason the item reports what was heard and never judges pronunciation. This is the one consumer that records a use from a streamed final; the streaming design otherwise keeps streamed text out of analytics, and names this consumer as its one exception. Read-aloud minutes count against the streaming monthly cap and are metered apart from voice messages, so the two can be told apart when the cap is reviewed. A recording no route can transcribe shows a connection message, keeps the mic for another try, and is never recorded as a miss.

**Scoring.** Correct reads and misses carry their own use types, `corRA` and `incRA`, classified as speaking, so they join voice messages and calls on the word card's speaking row and in the teacher summaries ([Adding a use type](analytics-system.instructions.md#adding-a-use-type)). A correct read earns what a correct listening answer earns. A miss is worth 0: the small negative XP on a wrong multiple-choice pick discourages guessing, and there is no guessing a read. The accuracy bonus applies as usual. Time a read-aloud item is on screen does not count against the speed bonus, because rushing a read defeats the point; the session clock itself runs as usual, so leaving the panel still costs. A read-aloud item is not a voice message, so it does not count toward the dashboard's speaking minutes, which are voice messages and calls.

**Microphone.** The first read-aloud item asks for microphone permission the way a voice message does. A refusal, or a device with no microphone, turns that item and the session's remaining read-aloud items into meaning exercises for the same words ([Loading & Generation Sequencing](#loading--generation-sequencing)); the next session tries again, so a learner who grants the permission later gets read-aloud items back.

---

## Message Practice (Toolbar)

### Target Selection

[`PracticeSelectionRepo`](../../lib/pangea/practice_activities/practice_selection_repo.dart) determines which tokens in a message become practice targets:

- Only tokens with `saveVocab = true` on their lemma (filters out punctuation, numbers, etc.)
- Only messages in the user's target language (L2)
- Deduplicated by lemma — if "running" and "runs" appear in the same message, only one is selected
- Capped at 5 targets per activity type per message (avoids overwhelming long messages)

Selections are cached per message for two days in [`PracticeSelectionRepo`](../../lib/routes/chat/toolbar/practice_exercises/practice_selection_repo.dart).

Token priority within each message uses the scoring formula described in [Target Prioritization](#target-prioritization-which-words-first) above.

### Practice Modes

[`MessagePracticeMode`](../../lib/pangea/toolbar/message_practice/message_practice_mode_enum.dart) defines the four toolbar modes: `listening`, `wordMeaning`, `wordEmoji`, `wordMorph`. Each mode maps to an `ActivityTypeEnum` and shows per-word buttons on the message. When all words in a mode are complete, the mode's icon turns gold.

### Controller

[`PracticeController`](../../lib/pangea/toolbar/message_practice/practice_controller.dart) manages per-message practice state:
- Fetches `PracticeSelection` on construction
- Generates activities on demand via [`PracticeRepo`](../../lib/pangea/practice_activities/practice_generation_repo.dart)
- Records answers via [`PracticeRecordController`](../../lib/pangea/toolbar/message_practice/practice_record_controller.dart)
- Plays TTS on correct answers for audio reinforcement (gated by the **Choices** audio setting)

---

## Activity Generation

[`PracticeRepo`](../../lib/routes/chat/toolbar/practice_exercises/practice_generation_repo.dart) is the central dispatch for generating exercises: it takes a request carrying a `PracticeTarget` (tokens + exercise type + optional morph feature), routes it to that type's generator, and returns the exercise. It keeps no cache of its own.

Every exercise type in use is assembled on the device. The generators build on content that does come from the choreographer — lemma meanings and emoji from the lemma dictionary, morph tags from the grammar constructs provider — but each of those is cached where it is fetched, so generating an exercise is not a paid call in its own right. What regenerating costs is stability: generators shuffle their choices and re-pick their distractors, so a regenerated exercise is a different exercise.

That stability is owned by the practice that asked for the exercise. [`PracticeController`](../../lib/routes/chat/toolbar/message_practice/practice_controller.dart) holds the exercises generated for one message in a [`PracticeExerciseMemo`](../../lib/routes/chat/toolbar/message_practice/practice_exercise_memo.dart), so leaving a word and coming back to it inside an open toolbar shows the same exercise; the memo dies with the toolbar. Reporting wrong lemma content drops that word's exercise, so the next fetch rebuilds it from the corrected content. Standalone practice generates each exercise once as it fills its session queue and needs no memo.

Exercises are deliberately never cached across practices or written to disk: a shared, longer-lived cache serves one learner the same drill — same distractors, same order — in separate sittings, and can outlive corrections made to the content behind it.

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
- **An exercise the learner can return to doesn't change under them.** Inside one open toolbar, revisiting a word shows the exercise already generated for it. Closing the toolbar ends that guarantee: the next open generates fresh exercises, with freshly shuffled choices.
- **Message practice never blocks on network.** Selection is local from cached token data; content fetches from choreo behind shimmer placeholders, never a blocking spinner.
- **Standalone practice gates the UI only on the first exercise.** The loading screen covers target selection (local analytics reads) plus generation of the first exercise; the remaining exercises are prefetched eagerly in the background — their example-message, audio, and event resolution runs concurrently so they're ready when reached — but the UI never waits on the full set. Selection stays cheap and resolves no example messages, audio, or events (see [Loading & Generation Sequencing](#loading--generation-sequencing)).
- **Emoji and meaning choices persist beyond the practice session.** They become the user's personal annotation on that lemma, visible in word cards and analytics.
- **All practice produces construct uses.** Whether from the toolbar or the standalone page, every answer is recorded as a `ConstructUseModel` that feeds into the analytics system.

## Future Work
*Last updated: 2026-10-19*

**Practice Types & Modalities**

- [pangeachat/client#3176](https://github.com/pangeachat/client/discussions/3176) — New type of practice exercise
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
- More activity types (fill-in-the-blank, sentence reordering)
