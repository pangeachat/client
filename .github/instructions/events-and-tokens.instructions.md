---
applyTo: "lib/pangea/events/**,lib/pangea/extensions/**"
---

# Events & Tokens — Matrix Event Data Model

Messages in Pangea carry rich metadata stored as Matrix events related to the main message. This doc covers custom event types, the token model, event wrappers, and how they connect.

## Event Hierarchy for a Message

Custom events are either embedded within the content of the original `m.room.message` or stored as child events linked to the message. These include:

1. **PangeaRepresentation** (`pangea.representation`): Representation (either text or speech-to-text transcription) of the message. The original sent text and orignal written text can be embedded within the original message content. Subsequent representations are sent as child events.
    
    1. **Tokens** (`pangea.tokens`): Tokens in the message. Should be embedded in the original message content, unless an error occured
    2. **ChoreoRecord** (`pangea.record`): Choreographer editing history for the message. Should be embedded in the original message content, if it exists.
2. **TextToSpeech** (`pangea.text_to_speech`): Text-to-speech audio for the message, stored as a child event.
3. **SpeechToText** (`pangea.translation`): Speech-to-text transcription of the message, usually embedded in original message contet, but can be sent as a child event of message.
4. **SttTranslation** (`pangea.stt_translation`): Translation of speech-to-text transcription, stored as a child event.

## Other Custom Event Types (`PangeaEventTypes`)

Defined in `lib/pangea/events/constants/pangea_event_types.dart`:

### Activities

| Type | Constant | Purpose |
|---|---|---|
| `pangea.activity_plan` | `activityPlan` | Activity plan definition |
| `pangea.activity_roles` | `activityRole` | Roles in a structured activity |
| `pangea.activity_summary` | `activitySummary` | Post-activity summary |

### Analytics & Learning

| Type | Constant | Purpose |
|---|---|---|
| `pangea.construct` | `construct` | A tracked learning construct |
| `pangea.construct_summary` | `constructSummary` | Aggregate construct data |
| `p.user_lemma_info` | `userSetLemmaInfo` | User-customized lemma info |
| `p.emoji` | `userChosenEmoji` | User-chosen emoji for a word |
| `p.analytics_settings` | `analyticsSettings` | Analytics display settings |
| `pangea.activity_room_ids` | `activityRoomIds` | List of saved activity room IDs |

### Room/Course Settings

| Type | Constant | Purpose |
|---|---|---|
| `pangea.bot_options` | `botOptions` | Bot behavior configuration |
| `pangea.capacity` | `capacity` | Room capacity limit |
| `pangea.course_plan` | `coursePlan` | Course plan reference |
| `pangea.teacher_mode` | `teacherMode` | Teacher mode toggle |
| `pangea.course_chat_list` | `courseChatList` | Course chat list default chat settings |

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
