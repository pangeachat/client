# Choreographer — Writing Assistance Flow

The choreographer is the client-side orchestrator for real-time writing assistance. It manages **IGC** (Interactive Grammar Correction) and **IT** (Interactive Translation), coordinating user text input, API calls, match display, and the creation of choreo records that are saved with sent messages.

## Architecture

```
Choreographer (ChangeNotifier)
├── PangeaTextController      ← Extended TextEditingController (tracks edit types)
├── IgcController              ← Grammar check matches
├── ITController               ← Translation step-by-step flow
└── ChoreographerErrorController ← Error state + backoff
```

### Key files

- `lib/pangea/choreographer/choreographer.dart` — Main orchestrator
- `lib/pangea/choreographer/igc/igc_controller.dart` — IGC state
- `lib/pangea/choreographer/it/it_controller.dart` — IT state
- `lib/pangea/choreographer/text_editing/pangea_text_controller.dart` — Text controller
- `lib/pangea/choreographer/choreo_record_model.dart` — Record of edits saved with message

## Flow

### 1. User types → debounce → IGC request

1. User types in chat input. `PangeaTextController` fires `_onChange`.
2. After debounce (`ChoreoConstants.msBeforeIGCStart`), `requestWritingAssistance()` is called.
3. `IgcController.getIGCTextData()` calls the `/grammar_v2` endpoint via `IgcRepo`.
4. Response contains a list of `SpanData` (matches) — grammar errors, out-of-target markers, normalization fixes.
5. Normalization matches (capitalization, punctuation) are auto-accepted. Grammar matches become `openMatches`.

### 2. Matches displayed → Span cards

1. Open matches render as underlines in the text field (via `EditTypeEnum.igc`).
2. Tapping a match opens a **span card** overlay (`span_card.dart`) showing the error and choices.
3. Additional detail is fetched lazily from `/span_details` via `SpanDataRepo`.

### 3. User resolves matches

Each match goes through `PangeaMatchState` with status transitions:

- `open` → `accepted` (user chose a replacement)
- `open` → `ignored` (user dismissed)
- `open` → `automatic` (normalization auto-applied)
- Any → `undo` (user reverted)

When a match is accepted/ignored, the `IgcController` fires `matchUpdateStream`. The `Choreographer` listens and:

- Updates the text via `textController.setSystemText()`
- Records the step in `ChoreoRecordModel`

### 4. Interactive Translation (IT)

If an IT-start match is found (the whole message is in L1):

1. `ITController.openIT()` is called, clearing the text field.
2. IT calls `/it_initialstep` with the source text.
3. Server returns step-by-step continuances (partial translations the user selects from).
4. Each accepted continuance appends to the text field and is recorded in `ChoreoRecordModel`.
5. When IT finishes or is dismissed, choreo mode reverts to IGC.

### 5. Sending

On send, `Choreographer.getMessageContent()`:

1. Calls `/tokenize` to get `PangeaToken` data for the final text.
2. Builds `PangeaMessageContentModel` containing:
   - The final message text
   - `ChoreoRecordModel` (full editing history)
   - `PangeaRepresentation` for original written text (if IT was used)
   - `PangeaMessageTokens` (token/lemma/morph data)

## Key Models

| Model                   | File                                | Purpose                                                                   |
| ----------------------- | ----------------------------------- | ------------------------------------------------------------------------- |
| `SpanData`              | `igc/span_data_model.dart`          | A grammar/translation match span (offset, length, choices, message, rule) |
| `PangeaMatch`           | `igc/pangea_match_model.dart`       | SpanData + status (open/accepted/ignored/automatic)                       |
| `PangeaMatchState`      | `igc/pangea_match_state_model.dart` | Mutable wrapper tracking original vs updated match state                  |
| `ChoreoRecordModel`     | `choreo_record_model.dart`          | Full editing history: steps, open matches, original text                  |
| `ChoreoRecordStepModel` | `choreo_edit_model.dart`            | Single edit step (text before/after, accepted match)                      |
| `ITStepModel`           | `it/it_step_model.dart`             | One IT step with continuance choices                                      |
| `CompletedITStepModel`  | `it/completed_it_step_model.dart`   | Completed IT step with user's chosen continuance                          |
| `GoldRouteTrackerModel` | `it/gold_route_tracker_model.dart`  | Tracks the server's gold translation route                                |
| `IGCRequestModel`       | `igc/igc_request_model.dart`        | Request to `/grammar_v2`                                                  |
| `IGCResponseModel`      | `igc/igc_response_model.dart`       | Response from `/grammar_v2`                                               |
| `MatchRuleIdModel`      | `igc/match_rule_id_model.dart`      | Constants for match rule IDs (e.g., `interactiveTranslation`)             |

## API Endpoints

| Endpoint                 | Repo File                      | Purpose                                  |
| ------------------------ | ------------------------------ | ---------------------------------------- |
| `/choreo/grammar_v2`     | `igc/igc_repo.dart`            | Grammar check + IT-start detection       |
| `/choreo/span_details`   | `igc/span_data_repo.dart`      | Detailed data for a specific span        |
| `/choreo/it_initialstep` | `it/it_repo.dart`              | Interactive translation step             |
| `/choreo/tokenize`       | `events/repo/tokens_repo.dart` | Tokenize final text for message metadata |

## Edit Types (`EditTypeEnum`)

- `keyboard` — User typing
- `igc` — System applying IGC match
- `it` — System applying IT continuance
- `itDismissed` — IT dismissed, restoring source text

## Choreo Modes (`ChoreoModeEnum`)

- `igc` — Normal grammar correction mode
- `it` — Interactive translation mode (full-message L1→L2)

## Error Handling

- IGC/IT errors trigger exponential backoff (`_igcErrorBackoff *= 2`)
- Backoff resets on next successful request
- Errors are surfaced via `ChoreographerErrorController`
