# Span Card UI Redesign - Finalized Plan

## Overview

Redesign the `SpanCard` widget to improve UX and add user feedback capabilities. This document consolidates all decisions from the design Q&A.

---

## New Layout

### Visual Structure

```
┌─────────────────────────────────────────┐
│  [X]           🤖            [🚩]       │  <- Header: Close, BotFace, Flag
├─────────────────────────────────────────┤
│           Span Type Label               │  <- Error category (e.g., "Grammar")
├─────────────────────────────────────────┤
│  [ Choice 1 ]  [ Choice 2 ]  [ ... ]    │  <- ChoicesArray
├─────────────────────────────────────────┤
│     "Best choice feedback text..."      │  <- Feedback shown on open
├─────────────────────────────────────────┤
│     [ Ignore ]          [ Replace ]     │  <- Action buttons
└─────────────────────────────────────────┘
```

### Header Row Details

Follow `WordZoomWidget` pattern exactly:

```dart
SizedBox(
  height: 40.0,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconButton(
        color: Theme.of(context).iconTheme.color,
        icon: const Icon(Icons.close),
        onPressed: widget.showNextMatch,
      ),
      Flexible(
        child: Container(
          constraints: const BoxConstraints(minHeight: 40.0),
          alignment: Alignment.center,
          child: BotFace(width: 40, expression: BotExpression.idle),
        ),
      ),
      IconButton(
        color: Theme.of(context).iconTheme.color,
        icon: const Icon(Icons.flag_outlined),
        onPressed: _onFlagPressed,
      ),
    ],
  ),
),
```

---

## Color Scheme

### Underline Colors by Type

Use `AppConfig.primaryColor` (#8560E0) for IT/auto-apply types.

| Category      | Types                                            | Color                                     |
| ------------- | ------------------------------------------------ | ----------------------------------------- |
| IT/Auto-apply | `itStart`, `punct`, `diacritics`, `spell`, `cap` | `AppConfig.primaryColor.withOpacity(0.7)` |
| Grammar       | All `grammarTypes` list                          | `AppConfig.warning.withOpacity(0.7)`      |
| Word Choice   | All `wordChoiceTypes` list                       | `Colors.blue.withOpacity(0.7)`            |
| Style/Fluency | `style`, `fluency`                               | `Colors.teal.withOpacity(0.7)`            |
| Other/Unknown | Everything else                                  | `colorScheme.error.withOpacity(0.7)`      |

### Implementation

Add to `replacement_type_enum.dart`:

```dart
extension ReplacementTypeEnumColors on ReplacementTypeEnum {
  Color underlineColor(BuildContext context) {
    if (this == ReplacementTypeEnum.itStart || isAutoApply) {
      return AppConfig.primaryColor.withOpacity(0.7);
    }
    if (isGrammarType) {
      return AppConfig.warning.withOpacity(0.7);
    }
    if (isWordChoiceType) {
      return Colors.blue.withOpacity(0.7);
    }
    switch (this) {
      case ReplacementTypeEnum.style:
      case ReplacementTypeEnum.fluency:
        return Colors.teal.withOpacity(0.7);
      default:
        return Theme.of(context).colorScheme.error.withOpacity(0.7);
    }
  }
}
```

---

## Feedback Flow

### Flag Button (Explicit Feedback)

1. User taps 🚩 flag icon
2. Show `FeedbackDialog` for user to enter feedback text
3. Close span card, show spinning IGC indicator
4. Call grammar_v2 endpoint with feedback attached via new `IgcController.rerunWithFeedback()` method
5. Clear existing matches, replace with new response
6. Display new span card if matches exist

### Ignore Button (Auto-Feedback)

1. User taps "Ignore"
2. Fire-and-forget call to grammar_v2 with auto-generated feedback:
   ```
   "user ignored the correction ({old} -> {new}) without feedback. not sure why"
   ```
3. Don't wait for response, proceed to next match
4. Silent fail on errors (logged server-side for finetuning)

### Feedback Schema

Use existing `LLMFeedbackSchema` structure:

```dart
{
  "feedback": "user's feedback text",
  "content": { /* original IGCResponseModel as JSON */ }
}
```

### Implementation Details

1. **Store last response**: Add `IGCResponseModel? _lastResponse` field to `IgcController`
2. **New method**: Add `rerunWithFeedback(String feedbackText)` to `IgcController`
3. **Feedback always included**: No loading state needed - feedback text comes with initial response
4. **No snackbar initially**: Just use spinning IGC indicator (may add UX feedback later if too abrupt)

---

## Span Type Display

### Display Names

Add `displayName(context)` method to `ReplacementTypeEnum`:

| Type Category | Display String   |
| ------------- | ---------------- |
| Grammar types | "Grammar"        |
| Word choice   | "Word Choice"    |
| `spell`       | "Spelling"       |
| `punct`       | "Punctuation"    |
| `style`       | "Style"          |
| `fluency`     | "Fluency"        |
| `diacritics`  | "Accents"        |
| `cap`         | "Capitalization" |
| Other         | "Correction"     |

---

## Choices Behavior

### Alts vs Distractors

- **Alts**: Equally valid alternatives (e.g., "él" vs "ella" when gender ambiguous)
- **Distractors**: Intentionally wrong options to test learner

These arrive as `SpanChoice` objects in `SpanData.choices`.

### Selection Behavior

| Choice Type | On Select                           |
| ----------- | ----------------------------------- |
| Best        | Enable "Replace" button             |
| Alt         | Treat as accepted, apply that value |
| Distractor  | Show "try again" feedback           |

### Single Choice

If only one choice exists, show it without choice UI chrome.

---

## Button Behaviors

| Button  | Action                                             |
| ------- | -------------------------------------------------- |
| X       | Close card, show next match (same as Ignore)       |
| Replace | Apply selected choice, close card, show next match |
| Ignore  | Auto-feedback (fire-and-forget), show next match   |
| Flag    | Open feedback dialog, re-run WA with user feedback |

---

## Files to Modify

| File                          | Changes                                                  |
| ----------------------------- | -------------------------------------------------------- |
| `replacement_type_enum.dart`  | Add `underlineColor(context)` and `displayName(context)` |
| `pangea_text_controller.dart` | Update `_underlineColor` to use type-based colors        |
| `span_card.dart`              | Restructure layout per new design                        |
| `intl_en.arb`                 | Add new l10n strings                                     |

---

## Localization Strings

Add to `intl_en.arb`:

```json
{
  "spanFeedbackTitle": "Report correction issue",
  "spanTypeGrammar": "Grammar",
  "spanTypeWordChoice": "Word Choice",
  "spanTypeSpelling": "Spelling",
  "spanTypePunctuation": "Punctuation",
  "spanTypeStyle": "Style",
  "spanTypeFluency": "Fluency",
  "spanTypeAccents": "Accents",
  "spanTypeCapitalization": "Capitalization",
  "spanTypeCorrection": "Correction"
}
```

**TODO**: Run translation script after adding strings.

---

## Implementation Order

1. [ ] Update `replacement_type_enum.dart`
   - [ ] Add `underlineColor(context)` method
   - [ ] Add `displayName(context)` method
2. [ ] Update `pangea_text_controller.dart`
   - [ ] Change `_underlineColor` to use type-based colors
3. [ ] Add l10n strings to `intl_en.arb`
4. [ ] Update `igc_controller.dart`
   - [ ] Add `IGCResponseModel? _lastResponse` field
   - [ ] Store response in `getIGCTextData()` after fetch
   - [ ] Add `rerunWithFeedback(String feedbackText)` method
   - [ ] Add `sendAutoFeedback(PangeaMatch match)` method (fire-and-forget)
5. [ ] Restructure `span_card.dart`
   - [ ] Add header row (X, BotFace, Flag)
   - [ ] Add span type display row
   - [ ] Show feedback on card open (no loading state needed)
   - [ ] Wire up flag button to feedback flow
   - [ ] Wire up ignore button to auto-feedback
6. [ ] Test full flow

---

## Testing Considerations

- Verify underline colors display correctly for each error type
- Test feedback dialog flow end-to-end
- Test auto-feedback on ignore (verify silent fail)
- Ensure span card closes properly after all actions
- Test with various span types to verify type labels
- Test distractor selection shows "try again"
- Test alt selection applies the alt value

## NEXT STEPS

- Figure out why feedback isn't displaying
- Considering migrating to using match message field instead of choice feedback
