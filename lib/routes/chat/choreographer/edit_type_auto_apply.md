# Edit Type Auto-Apply Planning

## Current Behavior

The client currently auto-applies edits (without user interaction) based on a single condition:
- **Normalization errors**: Edits where the correction is the same as the original when normalized (punctuation, spacing, accents removed)

This is implemented in:
- [span_data_model.dart](igc/span_data_model.dart#L147) - `isNormalizationError()` method
- [igc_controller.dart](igc/igc_controller.dart#L43) - `openAutomaticMatches` getter
- [igc_controller.dart](igc/igc_controller.dart#L227) - `acceptNormalizationMatches()` method

Current `isNormalizationError()` logic:
```dart
bool isNormalizationError() {
  final correctChoice = choices?.firstWhereOrNull((c) => c.isBestCorrection)?.value;
  final l2Code = MatrixState.pangeaController.userController.userL2?.langCodeShort;

  return correctChoice != null &&
      l2Code != null &&
      normalizeString(correctChoice, l2Code) == normalizeString(errorSpan, l2Code);
}
```

The `normalizeString` function (in [text_normalization_util.dart](igc/text_normalization_util.dart)):
- Converts to lowercase
- Removes diacritics (language-specific)
- Replaces hyphens with spaces
- Removes punctuation
- Normalizes whitespace

## Proposed Change

Split auto-apply behavior based on **edit type** instead of just normalization matching.

### Questions to Answer

1. **What edit types should we distinguish?**
   - Punctuation-only edits
   - Accent/diacritic-only edits
   - Capitalization-only edits
   - Spelling errors
   - Grammar errors (conjugation, agreement, etc.)
   - Word choice / vocabulary suggestions
   - Code-switching corrections (L1 word replaced with L2)

2. **Which edit types should auto-apply?**
   - Current: All "normalization" edits (punctuation + accent + case)
   - Proposed: Make this configurable by type?

3. **Where does the edit type come from?**
   - Currently from `SpanData.rule` (has `Rule.id`, `Rule.category`, etc.)
   - Or from `SpanDataTypeEnum` (grammar, correction, etc.)
   - May need choreo/backend to provide explicit type classification

4. **What user interaction modes exist?**
   - Auto-apply (no interaction, edit applied silently)
   - Notification (edit applied but user is informed)
   - Selection (user must choose from options)
   - Full interaction (span card with explanation)

## Files to Modify

### Client-side (this repo)
- `igc/span_data_model.dart` - Add edit type classification methods
- `igc/igc_controller.dart` - Update auto-apply logic based on type
- `choreographer.dart` - Handle different interaction modes
- Potentially new enum for edit categories

### Backend (choreo)
- May need to return explicit edit type/category in response
- See [2-step-choreographer next_steps.md](../../../../../2-step-choreographer/app/handlers/wa/next_steps.md)

## Current SpanData Structure

```dart
class SpanData {
  final String? message;
  final String? shortMessage;
  final List<SpanChoice>? choices;
  final int offset;
  final int length;
  final String fullText;
  final SpanDataTypeEnum type;  // grammar, correction, etc.
  final Rule? rule;             // has id, category, description
}
```

## Tasks

- [ ] Define edit type categories/enum
- [ ] Determine classification logic (client-side vs server-side)
- [ ] Design interaction mode mapping (type → mode)
- [ ] Implement type classification in SpanData
- [ ] Update IgcController to use type-based auto-apply
- [ ] Add user preference support (optional)
- [ ] Coordinate with choreo backend if needed
