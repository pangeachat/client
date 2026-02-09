# Span Card UI Redesign Plan

## Overview

Redesign the `SpanCard` widget to improve UX and add user feedback capabilities. This document outlines the changes needed for the new layout and feedback flow.

## Decisions Made ✅

### 1. Feedback Endpoint Behavior ✅

**Decision**: Re-run WA analysis with feedback to get different/better correction

**Implementation notes**:

- Use `gpt_5_2` model on regeneration
- Use `prompt_version="verbose"`
- Pull at least 3 varied examples in
- Need choreo-side testing to verify feedback is included in re-run

### 2. Close Button (X) Behavior ✅

**Decision**: Close span card and show next match (same as current "Ignore")

### 3. Best Choice Feedback Display ✅

**Decision**: Show immediately on card open

> _Pedagogical note: Since the user has already seen their error highlighted and the choices displayed, the feedback explains "why" after they've had a chance to think about it. Hiding it behind a button adds friction without clear benefit._

### 4. Span Type Copy Format ✅

**Decision**: Use short labels defined in `replacement_type_enum.dart`

Will add `displayName(context)` method returning l10n strings like:

- "Grammar" / "Word Choice" / "Spelling" / "Punctuation" / "Style"

### 5. Color Scheme ✅

**Decision**: Use brand colors from `app_config.dart`:

- **Primary/Purple**: `AppConfig.primaryColor` (#8560E0) - for IT/auto-apply
- **Warning/Orange**: `AppConfig.warning` (rgba 210,124,12) - for grammar errors
- **Error/Red**: Use `colorScheme.error` - for unknown/other
- **Style/Teal**: Keep proposed teal for style/fluency
- **Word Choice**: Keep proposed blue

### 6. Auto-Feedback on Ignore ✅

**Decision**: Auto-submit feedback on ignore (fire-and-forget)

**Implementation**:

- Submit async, don't block UI
- Catch errors internally (silent fail)
- Default message: `"user ignored the correction ({old} -> {new}) without feedback. not sure why"`

### 7. Re-run Feedback Flow UX ✅

**Decision**: Close card → show spinning IGC indicator → snackbar with bot face "Got it! Recalculating..."

- Shows card again when complete if there are more matches
- Uses existing spinning indicator pattern in input bar

### 8. What if re-run returns no correction? ✅

**Decision**: Spinner turns green and it's done (no special message)

### 9. Choices Layout ✅

**Decision**: Include alts/distractors in initial WA call with expanded TSV format

---

## Discussion: Expanded TSV Format for Alts/Distractors

### Proposed Format

```
old	new	type	reason	alt_1	alt_2	distractor_1	distractor_2
```

### Your Pros

1. Include alts when subjective (gender ambiguity, etc.) - user can pick
2. Include distractors when it makes a good learning exercise
3. Single handler = less to finetune, less feedback loops to manage

### My Analysis on Complexity vs Quality

**Short answer**: I think it's fine, with some guardrails.

**Reasoning**:

1. **Column count is manageable** - 8 columns is still very parseable for the model. The current 4-column format works well; doubling it shouldn't degrade accuracy much.

2. **Optional columns help** - Making alt/distractor columns optional (empty when not applicable) keeps simple cases simple. The model only populates them when genuinely useful.

3. **Clear semantics matter most** - As long as the prompt clearly defines:
   - `alt_1/alt_2`: Equally valid alternatives (subjective/ambiguous cases)
   - `distractor_1/distractor_2`: Plausible-but-wrong options (learning exercise)

   ...the model should handle it fine.

4. **Finetuning examples will solidify it** - If your training examples show when to use alts vs not, the model will learn the pattern.

### Potential Risks

1. **Over-generation of alts** - Model might add alts when not needed. Mitigation: Prompt to say "only include alts if genuinely ambiguous"

2. **Distractor quality** - Bad distractors could confuse learners. Mitigation: Could validate distractors are grammatically plausible but semantically wrong

3. **Parsing edge cases** - Tab characters in reasons could break TSV. Already handled?

### My Recommendation

Go for it. The benefits (unified handler, better UX for ambiguous cases) outweigh the complexity cost. Just make sure:

- Clear prompt instructions on when to use each column
- Good training examples showing both populated and empty cases
- Keep distractor generation optional/conservative initially

---

## Follow-up Questions

### 10. Alts vs Distractors Distinction ✅

**Clarified**:

- **Alts**: All correct options given the context (e.g., "él" vs "ella" when gender unclear)
- **Distractors**: Intentionally wrong options to test the learner

### 11. What if user picks an alt? ✅

**Decision**: Treat as "accepted" - apply that alt as the correction

### 12. Distractor selection behavior ✅

**Decision**: Show "try again" feedback, don't apply the distractor

### 13. Empty alts/distractors ✅

**Decision**: Just show the single `new` choice (no choice UI for single option)

---

## All Questions Resolved ✅

No more open questions. Ready for implementation.

---

## Current Implementation

**File**: [span_card.dart](span_card.dart)

Current layout (top to bottom):

1. `ChoicesArray` - answer options
2. `_SpanCardFeedback` - feedback text with lightbulb button
3. `_SpanCardButtons` - Ignore / Replace buttons

## New Layout

### Visual Structure

```
┌─────────────────────────────────────────┐
│  [X]           🤖            [🚩]       │  <- Row 1: Close, BotFace, Flag
├─────────────────────────────────────────┤
│           Span Type Copy                │  <- Row 2: Error category label
├─────────────────────────────────────────┤
│  [ Choice 1 ]  [ Choice 2 ]  [ ... ]    │  <- Row 3: ChoicesArray
├─────────────────────────────────────────┤
│     "Best choice feedback text..."      │  <- Row 4: Best choice feedback
├─────────────────────────────────────────┤
│     [ Ignore ]          [ Replace ]     │  <- Row 5: Action buttons
└─────────────────────────────────────────┘
```

### Detailed Rows

1. **Top Row (Header)**
   - Left: X button (close overlay) - `IconButton(Icons.close)`
   - Center: Bot face - `BotFace(width: 40, expression: BotExpression.idle)`
   - Right: Flag button (feedback) - `IconButton(Icons.flag_outlined)`

2. **Span Type Row**
   - Display the error category from `match.updatedMatch.match.type`
   - Use `ReplacementTypeEnum.defaultPrompt(context)` for human-readable text
   - Consider adding l10n strings for each type's display name

3. **Choices Row**
   - Keep existing `ChoicesArray` widget
   - No changes needed here

4. **Best Choice Feedback Row**
   - Display `bestChoice.feedback` text when available
   - Show on card open (no button needed) since feedback is now always included
   - Fall back to loading state if feedback needs fetching

5. **Action Buttons Row**
   - Keep existing `_SpanCardButtons` widget
   - No changes needed here

## Underline Color by Type

### Files to Modify

**File**: [pangea_text_controller.dart](../text_editing/pangea_text_controller.dart)

Current `_underlineColor` method uses `match.match.rule?.id` to determine color. Change to use `match.match.type` (ReplacementTypeEnum).

### Proposed Color Mapping

Add extension method to `ReplacementTypeEnum`:

```dart
// In replacement_type_enum.dart
extension ReplacementTypeEnumColors on ReplacementTypeEnum {
  Color get underlineColor {
    if (isAutoApply) {
      return Colors.purple.withOpacity(0.7);  // punct, diacritics, spell, cap
    }
    if (isGrammarType) {
      return Colors.orange.withOpacity(0.7);  // grammar errors
    }
    if (isWordChoiceType) {
      return Colors.blue.withOpacity(0.7);    // word choice issues
    }
    // Higher-level suggestions
    switch (this) {
      case ReplacementTypeEnum.style:
      case ReplacementTypeEnum.fluency:
        return Colors.teal.withOpacity(0.7);
      case ReplacementTypeEnum.itStart:
        return Colors.purple.withOpacity(0.7);
      default:
        return Colors.red.withOpacity(0.7);   // other/unknown
    }
  }
}
```

Update `pangea_text_controller.dart`:

```dart
Color _underlineColor(PangeaMatch match) {
  if (match.status == PangeaMatchStatusEnum.automatic) {
    return const Color.fromARGB(187, 132, 96, 224);
  }

  // Use type-based coloring instead of rule ID
  return match.match.type.underlineColor;
}
```

## Feedback Flag Flow

### Reference Implementation

See activity feedback flow in:

- [activity_sessions_start_view.dart](../../activity_sessions/activity_session_start/activity_sessions_start_view.dart#L83-L139)
- [feedback_dialog.dart](../../common/widgets/feedback_dialog.dart)

### Flow Steps

1. User taps flag icon in SpanCard header
2. Show `FeedbackDialog` with optional text input
3. On submit, call WA endpoint with feedback
4. Show `FeedbackResponseDialog` with response
5. Close span card

### New Files to Create

1. **`span_feedback_request.dart`** - Request model for WA feedback
2. **`span_feedback_repo.dart`** - Repository to call WA endpoint with feedback

### Endpoint Integration

The WA endpoint already supports feedback via `GrammarRequestV2.feedback` field.

**Choreo endpoint**: `POST /choreo/grammar_v2`

**Request with feedback**:

```json
{
  "full_text": "original user text",
  "user_l1": "en",
  "user_l2": "es",
  "feedback": [
    {
      "user_feedback": "This correction doesn't make sense",
      "input": { ... original request ... },
      "output": { ... original response ... }
    }
  ]
}
```

### Implementation in SpanCard

```dart
// In SpanCardState

Future<void> _onFlagPressed() async {
  final feedback = await showDialog<String?>(
    context: context,
    builder: (context) => FeedbackDialog(
      title: L10n.of(context).spanFeedbackTitle,
      onSubmit: (feedback) => Navigator.of(context).pop(feedback),
      scrollable: false,
    ),
  );

  if (feedback == null || feedback.isEmpty) return;

  final resp = await showFutureLoadingDialog(
    context: context,
    future: () => SpanFeedbackRepo.submitFeedback(
      SpanFeedbackRequest(
        span: widget.match.updatedMatch.match,
        feedbackText: feedback,
        userId: Matrix.of(context).client.userID!,
        userL1: MatrixState.pangeaController.userController.userL1Code!,
        userL2: MatrixState.pangeaController.userController.userL2Code!,
      ),
    ),
  );

  if (resp.isError) return;

  await showDialog(
    context: context,
    builder: (context) => FeedbackResponseDialog(
      title: L10n.of(context).feedbackTitle,
      feedback: resp.result!.userFriendlyResponse,
      description: L10n.of(context).feedbackRespDesc,
    ),
  );

  // Close the span card
  widget.showNextMatch();
}
```

## Localization Strings Needed

Add to `intl_en.arb`:

```json
{
  "spanFeedbackTitle": "Report correction issue",
  "spanTypeGrammar": "Grammar",
  "spanTypeWordChoice": "Word Choice",
  "spanTypeSpelling": "Spelling",
  "spanTypePunctuation": "Punctuation",
  "spanTypeStyle": "Style",
  "spanTypeFluency": "Fluency"
}
```

## Files to Modify

| File                          | Changes                                                           |
| ----------------------------- | ----------------------------------------------------------------- |
| `span_card.dart`              | Restructure layout, add header row with X/BotFace/Flag            |
| `replacement_type_enum.dart`  | Add `underlineColor` extension, add `displayName(context)` method |
| `pangea_text_controller.dart` | Update `_underlineColor` to use type-based colors                 |

## New Files to Create

| File                         | Purpose                                |
| ---------------------------- | -------------------------------------- |
| `span_feedback_request.dart` | Request model for span feedback        |
| `span_feedback_repo.dart`    | API calls for submitting span feedback |

## Implementation Order

1. [ ] Update `replacement_type_enum.dart` with `underlineColor` and `displayName`
2. [ ] Update `pangea_text_controller.dart` to use type-based underline colors
3. [ ] Create `span_feedback_request.dart` and `span_feedback_repo.dart`
4. [ ] Restructure `span_card.dart` layout:
   - [ ] Add header row (X, BotFace, Flag)
   - [ ] Add span type display row
   - [ ] Move ChoicesArray
   - [ ] Show best choice feedback on open
   - [ ] Implement flag button handler
5. [ ] Add localization strings
6. [ ] Test full flow

## Testing Considerations

- Verify underline colors display correctly for each error type
- Test feedback dialog flow end-to-end
- Ensure span card closes properly after feedback submission
- Test with various span types to verify type label displays correctly

---

## Pre-Implementation Questions

### 1. Re-run Feedback Flow Architecture

The plan says feedback triggers a re-run of WA analysis with `gpt_5_2` model and `prompt_version="verbose"`.

- **Q1a**: Does the choreo endpoint (`POST /choreo/grammar_v2`) already support the `prompt_version` parameter, or does this need to be added?
- **Q1b**: Where should the model override (`gpt_5_2`) be configured? On the request from the client, or hardcoded in the handler when feedback is present?

this will be handled server-side. the client just needs to send the feedback in the request object. you can remove the notes about the serverside implemention, those have been added to server doc wa/next_steps.md

### 2. Alts/Distractors in TSV Format

The plan mentions expanding TSV format to include `alt_1`, `alt_2`, `distractor_1`, `distractor_2` columns.

- **Q2a**: Is this TSV format expansion already implemented in choreo, or is this a future change we're planning for?
- **Q2b**: If not implemented yet, should the SpanCard redesign proceed without the alts/distractors UI, or should we stub it out?

don't worry about this. they'll be SpanChoices in SpanData

### 3. SpanFeedbackRepo Return Type

The plan shows `resp.result!.userFriendlyResponse` after submitting feedback (similar to activity feedback).

- **Q3**: For span feedback, what should the response contain? A new `GrammarResponseV2` with re-analyzed corrections? Or a simple acknowledgment with `userFriendlyResponse`?

the client will call grammar_v2 endpoint again with feedback. it'll return a new grammar response object.

### 4. Auto-Feedback on Ignore

The plan states auto-submit feedback on ignore with message: `"user ignored the correction ({old} -> {new}) without feedback"`.

- **Q4**: Should this auto-feedback actually trigger a re-run of WA analysis (like explicit feedback does), or should it just be logged/stored for finetuning purposes without re-analysis?

it should send it via the grammar_v2 endpoint again but not worry about the result. the choreo will audit and store.

### 5. Localization

The plan lists new l10n strings to add.

- **Q5**: Should I add these to `intl_en.arb` only, or are there other language files that need the new keys as well?

some may be existing, others will be new. just add to intl_en.arb. make a TODO about them to run the translation script.

### 6. Color Implementation

The plan uses `Colors.purple.withOpacity(0.7)` for auto-apply types, but references `AppConfig.primaryColor` (#8560E0) in the decisions section.

- **Q6**: Should I use the literal `Colors.purple.withOpacity(0.7)` or the app's `AppConfig.primaryColor` with opacity? (They're slightly different shades)

use the primary with opacity. it's what itStart uses.

---

## Follow-up Questions (Round 2)

### 7. Feedback Request Structure

The existing `GrammarRequestV2` has a `feedback` field of type `List<LLMFeedbackSchema>`. Looking at the activity feedback flow, it uses a separate `ActivityFeedbackRequest` model.

- **Q7a**: Should the span feedback flow modify the existing `IGCController` to re-call the grammar endpoint with feedback attached to the request, or create a separate `SpanFeedbackRepo` that wraps the grammar call?

reuse the existing flow unless you spot complications with that.

- **Q7b**: What fields should be included in the feedback object? Just `user_feedback` text, or also the original `input`/`output` as shown in the plan's JSON example?

LLMFeedbackSchema calls for the response object plus the user_feedback text

### 8. UI Flow on Re-run

The plan says: "Close card → show spinning IGC indicator → snackbar with bot face 'Got it! Recalculating...'"

- **Q8a**: After the re-run completes, if the same span now has a different correction (or no correction), how should we update the existing match state? Replace in-place, or clear all matches and re-process?

it will return all new matches. clear the IGC match data and replace it with new

- **Q8b**: Should the snackbar be shown, or is the spinning IGC indicator sufficient feedback?

sure, let's skip the snackbar for now and see.

### 9. SpanCard Header Layout

The plan shows `[X]  🤖  [🚩]` in the header.

- **Q9**: Should the X button and Flag button be the same size for visual symmetry, or should flag be smaller/less prominent?

same size and color for visual symmetry. see the word card for example and follow that exactly

---

## All Questions Resolved ✅

Ready to implement. Summary of key decisions from Q&A:

1. **Feedback flow**: Reuse existing `IGCController` to call grammar endpoint with feedback attached
2. **Feedback schema**: `LLMFeedbackSchema` with `feedback` (user text) + `content` (original response object)
3. **Re-run result**: Clear existing IGC matches and replace with new response
4. **No snackbar**: Just use spinning IGC indicator
5. **Header layout**: Follow `WordZoomWidget` exactly - both buttons same size/color using `IconButton` with `Theme.of(context).iconTheme.color`
6. **Colors**: Use `AppConfig.primaryColor` with opacity for IT/auto-apply
7. **Localization**: Add to `intl_en.arb` only, TODO for translation script

---

## Follow-up Questions (Round 3)

### 10. Best Choice Feedback Loading State

The original plan mentioned "Fall back to loading state if feedback needs fetching."

**Q10**: Is feedback always included in the initial WA response now (so no fetching needed), or should we still handle a loading state for feedback?

yes, both feedback and choices will always be included

### 11. FeedbackResponseDialog After Flag

The original plan showed a `FeedbackResponseDialog` after submitting feedback, but Q8b decided "skip the snackbar" and Q3 clarified the response is a new `GrammarResponseV2` (not a `userFriendlyResponse` string).

**Q11**: After flag feedback re-run, should we:

- (A) Just close card → spinner → show new matches (no dialog), or
- (B) Show a dialog acknowledging the feedback before showing new results?

i think we probably need something. just closing the card would be abrupt. that's why i was thinking the snackbar. let's start without it and see though.

### 12. Re-run Trigger Method

The feedback calls grammar_v2 which returns a new response.

**Q12**: How does the SpanCard trigger the re-run through IGCController? Should it:

- (A) Call a new method like `igcController.rerunWithFeedback(feedback, originalResponse)`, or
- (B) Call the existing flow but with feedback attached to the request somehow?

probably a new method is a good idea so we can add in any logic needed for this

### 13. Original Response Reference

`LLMFeedbackSchema` needs the original response (`content` field).

yes. send the contested grammar response

**Q13**: Where is the original `GrammarResponseV2` stored that we can reference when building the feedback object? Is it on `IGCController` or `Choreographer`?

i'm not sure exactly. actually, i think it should be accessible via igc_repo.dart which will have cached it

---

## All Round 3 Questions Answered ✅

Summary of Round 3 decisions:

10. **Feedback always included**: No loading state needed for feedback text
11. **Post-feedback UX**: Start without snackbar/dialog, may add later if too abrupt
12. **New method needed**: Create `igcController.rerunWithFeedback(feedback, originalResponse)`
13. **Original response location**: Access via `IgcRepo` cache (keyed by request hashcode)

---

## Follow-up Questions (Round 4)

### 14. IgcRepo Cache Access

Looking at `igc_repo.dart`, the cache is keyed by `IGCRequestModel.hashCode.toString()` and stores `Future<IGCResponseModel>`. The cache is private (`_igcCache`).

**Q14**: To access the cached response for feedback, should I:

- (A) Add a public method to `IgcRepo` like `getLastResponse()` or `getCachedResponse(request)`, or
- (B) Store the response on `IgcController` after fetch completes (simpler)?

not sure. use your judgment.
