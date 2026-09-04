import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/utils/text_editing_value_caret_extension.dart';

/// The composer's autocomplete splits the message at the caret twice — once to
/// find suggestions for the word being typed, once to insert the chosen one.
/// A controller that has never been focused reports no caret at all, and the
/// raw offset arithmetic answers that with `substring(0, -1)` (CLIENT-EKB).
void main() {
  group('canSplitAtCaret', () {
    test('a caret inside the text can be split at', () {
      expect(
        const TextEditingValue(
          text: 'hey :smi',
          selection: TextSelection.collapsed(offset: 4),
        ).canSplitAtCaret,
        isTrue,
      );
    });

    test('a caret at either end can be split at', () {
      expect(
        const TextEditingValue(
          text: 'hey',
          selection: TextSelection.collapsed(offset: 0),
        ).canSplitAtCaret,
        isTrue,
      );
      expect(
        const TextEditingValue(
          text: 'hey',
          selection: TextSelection.collapsed(offset: 3),
        ).canSplitAtCaret,
        isTrue,
      );
    });

    test('a composer that has never been focused has no caret', () {
      const neverFocused = TextEditingValue(text: 'hey');
      expect(
        neverFocused.selection.baseOffset,
        -1,
        reason:
            'the default selection of a TextEditingValue, and what a '
            'controller reports until something places the caret',
      );
      expect(neverFocused.canSplitAtCaret, isFalse);
    });

    test('a range selection is not a caret', () {
      expect(
        const TextEditingValue(
          text: 'hey there',
          selection: TextSelection(baseOffset: 0, extentOffset: 3),
        ).canSplitAtCaret,
        isFalse,
      );
    });

    test('an offset past the end of the text is not a caret', () {
      expect(
        const TextEditingValue(
          text: 'hey',
          selection: TextSelection.collapsed(offset: 4),
        ).canSplitAtCaret,
        isFalse,
      );
    });
  });

  group('the slices around the caret', () {
    test('a mid-text caret splits the text, dropping the character at it', () {
      const value = TextEditingValue(
        text: 'hey :smi there',
        selection: TextSelection.collapsed(offset: 8),
      );
      expect(value.textBeforeCaret, 'hey :smi');
      expect(
        value.textAfterCaret,
        'there',
        reason:
            'the character at the caret is deliberately dropped — the '
            'suggestion replaces the separator the trigger word ends on',
      );
    });

    test('a caret at the end leaves nothing after it', () {
      const value = TextEditingValue(
        text: 'hey :smi',
        selection: TextSelection.collapsed(offset: 8),
      );
      expect(value.textBeforeCaret, 'hey :smi');
      expect(value.textAfterCaret, '');
    });

    test('a caret at the start leaves nothing before it', () {
      const value = TextEditingValue(
        text: 'hey',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(value.textBeforeCaret, '');
      expect(value.textAfterCaret, 'ey');
    });
  });

  test('the raw arithmetic is what throws on a composer with no caret', () {
    const neverFocused = TextEditingValue(text: 'hey');
    expect(
      () => neverFocused.text.substring(0, neverFocused.selection.baseOffset),
      throwsRangeError,
      reason:
          'the guard exists because of this — the expression both call '
          'sites used to run inline',
    );
  });
}
