---
applyTo: "lib/pangea/choreographer/**"
---

# Choreographer — Writing Assistance Flow

The choreographer is the client-side orchestrator for real-time writing assistance. It coordinates user text input, API calls to `/grammar_v2`, match display, and the creation of choreo records saved with sent messages.

> **⚠️ IT (Interactive Translation) is deprecated.** The `it/` directory, `ITController`, and `/it_initialstep` endpoint are still wired into the choreographer but are being phased out. IT will become just another match type returned by IGC. Do not add new IT functionality.

## Architecture

```
Choreographer (ChangeNotifier)
├── PangeaTextController           ← Extended TextEditingController (tracks edit types)
├── IgcController                   ← Grammar check matches (primary flow)
├── ITController                    ← ⚠️ DEPRECATED — Translation step-by-step flow
├── ChoreographerErrorController    ← Error state + backoff
└── ChoreographerStateExtension     ← AssistanceStateEnum derivation
```

### Key files

| File | Purpose |
|---|---|
| `choreographer.dart` | Main orchestrator (ChangeNotifier) |
| `choreographer_state_extension.dart` | Derives `AssistanceStateEnum` from current state |
| `assistance_state_enum.dart` | UI states: noSub, noMessage, notFetched, fetching, fetched, complete, error |
| `choreo_mode_enum.dart` | `igc` (active) or `it` (⚠️ deprecated) |
| `choreo_record_model.dart` | Record of edits saved with message |
| `igc/igc_controller.dart` | IGC state management (437 lines) |
| `igc/replacement_type_enum.dart` | Granular match type taxonomy (grammar, surface, word-choice, etc.) |
| `igc/autocorrect_popup.dart` | Undo popup for auto-applied corrections |
| `text_editing/pangea_text_controller.dart` | Text controller with edit type tracking |
| `it/it_controller.dart` | ⚠️ DEPRECATED — IT state |

## Flow

### 1. User types → debounce → IGC request

1. User types in chat input. `PangeaTextController` fires `_onChange`.
2. After debounce (`ChoreoConstants.msBeforeIGCStart`), `requestWritingAssistance()` is called.
3. `IgcController.getIGCTextData()` calls `/grammar_v2` via `IgcRepo`.
4. Response contains a list of `SpanData` (matches) — grammar errors, out-of-target markers, normalization fixes.
5. Auto-apply matches (punct, diacritics, spell, cap) are accepted automatically via `acceptNormalizationMatches()`. Grammar/word-choice matches become `openMatches`.

### 2. Matches displayed → Span cards

1. Open matches render as colored underlines in the text field (colors set by `ReplacementTypeEnum.underlineColor()`).
2. Tapping a match opens a **span card** overlay (`span_card.dart`) showing the error category (`ReplacementTypeEnum.displayName()`), choices, and the error message.
3. Auto-applied corrections show an `AutocorrectPopup` with undo capability.

### 3. User resolves matches

Each match goes through `PangeaMatchState` with status transitions:

- `open` → `accepted` (user chose a replacement)
- `open` → `ignored` (user dismissed)
- `open` → `automatic` (auto-apply correction)
- Any → `undo` (user reverted)

When a match is accepted/ignored, the `IgcController` fires `matchUpdateStream`. The `Choreographer` listens and:

- Updates the text via `textController.setSystemText()`
- Records the step in `ChoreoRecordModel`

### 4. Feedback rerun

If the user is unsatisfied with results, `rerunWithFeedback(feedbackText)` re-calls IGC with user feedback and the previous request/response context (`_lastRequest`, `_lastResponse`).

**What the client sends**: The feedback request sends `List<LLMFeedbackSchema>` items on the request body. Each item carries `feedback` (optional string), `content` (the previous response for context), and `score` (optional int, 0–10). The score lets native speakers approve content (9–10) or reject it (0–6), while learners typically send a low score with corrective text. We'll probably just do 0 or 10 corresponding to thumbs up/down, but the schema supports finer granularity if needed.

**What the server does with it**: The router extracts `matrix_user_id` from the auth token and passes it along with the feedback list to `get()`. When feedback is present, `get()` builds an `Audit` internally (score + auditor + feedback text) and appends it to the CMS document (fire-and-forget). If the score indicates rejection (< 7), `get()` regenerates with an escalated model. The human judgment (who rejected/approved, why, when) lives on the `res.audit` array. See the server-side inference doc's Feedback Architecture section for the full flow.

**Native speaker approval**: When a native speaker sends score 9–10, the server persists the audit (upgrading the doc to fine-tuning eligible) and returns the cached response without regeneration.

### 5. Sending

On send, `Choreographer.getMessageContent()`:

1. Calls `/tokenize` to get `PangeaToken` data for the final text (with exponential backoff on errors).
2. Builds `PangeaMessageContentModel` containing:
   - The final message text
   - `ChoreoRecordModel` (full editing history)
   - `PangeaRepresentation` for original written text (if IT was used)
   - `PangeaMessageTokens` (token/lemma/morph data)

## AssistanceStateEnum

Derived in `choreographer_state_extension.dart`. Drives the send-button color and UI hints:

| State | Meaning |
|---|---|
| `noSub` | User has no active subscription |
| `noMessage` | Text field is empty |
| `notFetched` | Text entered but IGC hasn't run yet |
| `fetching` | IGC request in flight |
| `fetched` | Matches present — user needs to resolve them |
| `complete` | All matches resolved, ready to send |
| `error` | IGC error (backoff active) |

## ReplacementTypeEnum — Match Type Taxonomy

Defined in `igc/replacement_type_enum.dart`. Categories returned by `/grammar_v2`:

| Category | Types | Behavior |
|---|---|---|
| **Client-only** | `definition`, `practice`, `itStart` | Not from server; `itStart` triggers deprecated IT flow |
| **Grammar** (~21 types) | `verbConjugation`, `verbTense`, `verbMood`, `subjectVerbAgreement`, `genderAgreement`, `numberAgreement`, `caseError`, `article`, `preposition`, `pronoun`, `wordOrder`, `negation`, `questionFormation`, `relativeClause`, `connector`, `possessive`, `comparative`, `passiveVoice`, `conditional`, `infinitiveGerund`, `modal` | Orange underline, user must accept/ignore |
| **Surface corrections** | `punct`, `diacritics`, `spell`, `cap` | Auto-applied (no user interaction), undo via `AutocorrectPopup` |
| **Word choice** | `falseCognate`, `l1Interference`, `collocation`, `semanticConfusion` | Blue underline, user must accept/ignore |
| **Higher-level** | `transcription`, `style`, `fluency`, `didYouMean`, `translation`, `other` | Teal (style/fluency) or error color |

Key extension helpers: `isAutoApply`, `isGrammarType`, `isWordChoiceType`, `underlineColor()`, `displayName()`, `fromString()` (handles legacy snake_case and old type names like `grammar` → `subjectVerbAgreement`).

## Key Models

| Model | File | Purpose |
|---|---|---|
| `SpanData` | `igc/span_data_model.dart` | A match span (offset, length, choices, message, rule, `ReplacementTypeEnum`) |
| `PangeaMatch` | `igc/pangea_match_model.dart` | SpanData + status |
| `PangeaMatchState` | `igc/pangea_match_state_model.dart` | Mutable wrapper tracking original vs updated match state |
| `ChoreoRecordModel` | `choreo_record_model.dart` | Full editing history: steps, open matches, original text |
| `ChoreoRecordStepModel` | `choreo_edit_model.dart` | Single edit step (text before/after, accepted match) |
| `IGCRequestModel` | `igc/igc_request_model.dart` | Request to `/grammar_v2` |
| `IGCResponseModel` | `igc/igc_response_model.dart` | Response from `/grammar_v2` |
| `MatchRuleIdModel` | `igc/match_rule_id_model.dart` | Rule ID constants (⚠️ `tokenNeedsTranslation`, `tokenSpanNeedsTranslation`, `l1SpanAndGrammar` — not currently sent by server) |
| `AutocorrectPopup` | `igc/autocorrect_popup.dart` | Undo widget for auto-applied corrections |

## API Endpoints

| Endpoint | Repo File | Status |
|---|---|---|
| `/choreo/grammar_v2` | `igc/igc_repo.dart` | ✅ Active — primary IGC endpoint |
| `/choreo/tokenize` | `events/repo/tokens_repo.dart` | ✅ Active — tokenizes final text on send |
| `/choreo/span_details` | `igc/span_data_repo.dart` | ❌ Dead code — `SpanDataRepo` class is defined but never imported anywhere |
| `/choreo/it_initialstep` | `it/it_repo.dart` | ⚠️ Deprecated — IT flow |
| `/choreo/contextual_definition` | `contextual_definition_repo.dart` | ⚠️ Deprecated — only used by IT's `word_data_card.dart` |

## Edit Types (`EditTypeEnum`)

- `keyboard` — User typing
- `igc` — System applying IGC match
- `it` — ⚠️ Deprecated — System applying IT continuance
- `itDismissed` — ⚠️ Deprecated — IT dismissed, restoring source text

## Deprecated: SpanChoiceTypeEnum

In `igc/span_choice_type_enum.dart`:
- `bestCorrection` — `@Deprecated('Use suggestion instead')`
- `bestAnswer` — `@Deprecated('Use suggestion instead')`
- `suggestion` — Active replacement

## Error Handling

- IGC and token errors trigger exponential backoff (`_igcErrorBackoff *= 2`, `_tokenErrorBackoff *= 2`)
- Backoff resets on next successful request
- Errors surfaced via `ChoreographerErrorController`
- Error state exposed in `AssistanceStateEnum.error`

## ⚠️ Deprecated: Interactive Translation (IT)

> **Do not extend.** IT is being deprecated. Translation will become a match type within IGC.

The `it/` directory still contains `ITController`, `ITRepo`, `ITStepModel`, `CompletedITStepModel`, `GoldRouteTrackerModel`, `it_bar.dart`, `it_feedback_card.dart`, and `word_data_card.dart`. The choreographer still wires up IT via `_onOpenIT()` / `_onCloseIT()` / `_onAcceptContinuance()`, triggered when an `itStart` match is found. The `it_bar.dart` widget is still imported by `chat_input_bar.dart`.

This entire flow will be removed once testing confirms IT is no longer needed as a separate mode.
