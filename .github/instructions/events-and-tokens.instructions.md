---
applyTo: "lib/pangea/events/**,lib/pangea/extensions/**"
---

# Events & Tokens — Matrix Event Data Model

Messages in Pangea carry rich metadata stored as Matrix events related to the main message. This doc covers custom event types, the token model, event wrappers, and how they connect.

## Event Hierarchy for a Message

When a user sends a message, the client creates a tree of related Matrix events:

```
m.room.message (the chat message)
├── pangea.representation        ← PangeaRepresentation (sent text + lang)
│   ├── pangea.tokens            ← PangeaMessageTokens (tokenized text)
│   └── pangea.record            ← ChoreoRecordModel (editing history)
├── pangea.representation        ← (optional: L1 original if IT was used)
│   └── pangea.tokens
├── pangea.translation           ← Full-text translation
├── pangea.activity_req          ← Request to generate practice activities
├── pangea.activity_res          ← Generated practice activity
├── pangea.activity_completion   ← User's activity completion record
└── pangea.stt_translation       ← Speech-to-text translation
```

## Custom Event Types (`PangeaEventTypes`)

Defined in `lib/pangea/events/constants/pangea_event_types.dart`:

### Message-related

| Type | Constant | Purpose |
|---|---|---|
| `pangea.representation` | `representation` | A text representation with language code |
| `pangea.tokens` | `tokens` | Tokenized text (lemmas, POS, morphology) |
| `pangea.record` | `choreoRecord` | Choreographer editing history |
| `pangea.translation` | `translation` | Full-text translation |
| `pangea.stt_translation` | `sttTranslation` | Speech-to-text translation |

### Activities

| Type | Constant | Purpose |
|---|---|---|
| `pangea.activity_req` | `activityRequest` | Request server to generate activities |
| `pangea.activity_res` | `pangeaActivity` | A practice activity for a message |
| `pangea.activity_completion` | `activityRecord` | Per-user activity completion record |
| `pangea.activity_plan` | `activityPlan` | Activity plan definition |
| `pangea.activity_roles` | `activityRole` | Roles in a structured activity |
| `pangea.activity_summary` | `activitySummary` | Post-activity summary |

### Analytics & Learning

| Type | Constant | Purpose |
|---|---|---|
| `pangea.construct` | `construct` | A tracked learning construct |
| `pangea.construct_summary` | `constructSummary` | Aggregate construct data |
| `pangea.summaryAnalytics` | `summaryAnalytics` | Summary analytics data |
| `pangea.analytics_profile` | `profileAnalytics` | User analytics profile |
| `pangea.activities_profile` | `profileActivities` | User activities profile |
| `pangea.analytics_settings` | `analyticsSettings` | Analytics display settings |
| `p.user_lemma_info` | `userSetLemmaInfo` | User-customized lemma info |
| `p.emoji` | `userChosenEmoji` | User-chosen emoji for a word |

### Room/Course Settings

| Type | Constant | Purpose |
|---|---|---|
| `pangea.class` | `languageSettings` | Room language configuration |
| `p.rules` | `rules` | Room rules |
| `pangea.roomtopic` | `roomInfo` | Room topic info |
| `pangea.bot_options` | `botOptions` | Bot behavior configuration |
| `pangea.capacity` | `capacity` | Room capacity limit |
| `pangea.course_plan` | `coursePlan` | Course plan reference |
| `p.course_user` | `courseUser` | User's course enrollment |
| `pangea.teacher_mode` | `teacherMode` | Teacher mode toggle |
| `pangea.course_chat_list` | `courseChatList` | Course chat list |

### Audio & Media

| Type | Constant | Purpose |
|---|---|---|
| `p.audio` | `audio` | Audio attachment |
| `pangea.transcript` | `transcript` | Audio transcript |
| `p.rule.text_to_speech` | `textToSpeechRule` | TTS settings |

### User & Misc

| Type | Constant | Purpose |
|---|---|---|
| `pangea.user_age` | `userAge` | User age bracket |
| `m.report` | `report` | Content report |
| `p.rule.analytics_invite` | `analyticsInviteRule` | Analytics sharing rules |
| `p.analytics_request` | `analyticsInviteContent` | Analytics sharing request |
| `pangea.regeneration_request` | `regenerationRequest` | Content regeneration request |
| `pangea.activity_room_ids` | `activityRoomIds` | Activity room references |

## Core Data Models

### PangeaToken (`events/models/pangea_token_model.dart`)

The fundamental unit of linguistic analysis. Each token represents one word/unit.

```
PangeaToken
├── text: PangeaTokenText      ← {content: "running", offset: 5}
├── lemma: Lemma               ← {text: "run", saveVocab: true, form: "run"}
├── pos: String                ← "VERB" (Universal Dependencies POS tag)
└── morph: Map<MorphFeaturesEnum, String>  ← {Tense: "Pres", VerbForm: "Part"}
```

- POS tags follow [Universal Dependencies](https://universaldependencies.org/u/pos/)
- Morph features follow [Universal Dependencies features](https://universaldependencies.org/u/feat/)
- Lemma includes `saveVocab` flag for vocab tracking

### PangeaMessageTokens (`events/models/tokens_event_content_model.dart`)

Container for a tokenized message, stored as `pangea.tokens` event:

- `tokens: List<PangeaToken>` — tokenized words
- `detections: List<LanguageDetectionModel>?` — per-span language detection

### PangeaRepresentation (`events/models/representation_content_model.dart`)

A text representation of a message, stored as `pangea.representation` event:

- `text` — the text content
- `langCode` — detected language
- `originalSent` — true if this is the text that was actually sent
- `originalWritten` — true if this is what the user originally typed

Interpretation matrix:

| `originalSent` | `originalWritten` | Meaning |
|:-:|:-:|---|
| ✓ | ✗ | Text went through IGC/IT before sending |
| ✗ | ✗ | Added by another user (e.g., translation) |
| ✓ | ✓ | User wrote and sent as-is (L1 or perfect L2) |
| ✗ | ✓ | User's original L1 that was then translated via IT |

## Event Wrappers

### PangeaMessageEvent (`events/event_wrappers/pangea_message_event.dart`)

Wraps a Matrix `Event` of type `m.room.message` and provides access to all Pangea child events (representations, tokens, choreo records, translations, activities, etc.). This is the primary object used by the toolbar and reading assistance.

Key capabilities:

- Access tokens for the message
- Get translations and representations
- Trigger TTS/STT
- Get associated practice activities

### PangeaRepresentationEvent (`events/event_wrappers/pangea_representation_event.dart`)

Wraps a `pangea.representation` event. Provides typed access to `PangeaRepresentation` content.

### PangeaChoreoEvent (`events/event_wrappers/pangea_choreo_event.dart`)

Wraps a `pangea.record` event. Provides typed access to `ChoreoRecordModel` (editing history).

## Room Extensions for Events

`lib/pangea/extensions/room_events_extension.dart` extends Matrix `Room` with methods to:

- Query child events by type
- Find representations and tokens for a message
- Access pangea-specific event data

## Token Flow: Writing → Saving → Reading

1. **Writing**: Choreographer gets tokens from `/tokenize` on send
2. **Saving**: `PangeaMessageContentModel` bundles tokens + choreo record + representations → saved as Matrix child events
3. **Reading**: `PangeaMessageEvent` loads child events → toolbar uses `PangeaToken` list for word cards, practice activities, analytics
