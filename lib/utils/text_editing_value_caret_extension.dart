import 'package:flutter/widgets.dart';

extension TextEditingValueCaretExtension on TextEditingValue {
  /// Whether [selection] marks a single caret that [text] can be split at.
  ///
  /// A controller that has never been focused reports
  /// `TextSelection.collapsed(offset: -1)` — the default [TextEditingValue]
  /// selection — so slicing at the offset without asking reaches
  /// `String.substring` as a negative index and throws (CLIENT-EKB).
  ///
  /// Ask this before reading [textBeforeCaret] or [textAfterCaret]; both
  /// assume the offset is a real position in [text].
  bool get canSplitAtCaret =>
      selection.isCollapsed &&
      selection.baseOffset >= 0 &&
      selection.baseOffset <= text.length;

  /// The text up to the caret — the word being typed ends here, so this is
  /// what the composer matches suggestions against and replaces.
  String get textBeforeCaret => text.substring(0, selection.baseOffset);

  /// The text after the caret, less the character at it: an inserted
  /// suggestion carries its own trailing separator, so keeping the old one
  /// would double it.
  String get textAfterCaret => selection.baseOffset >= text.length
      ? ''
      : text.substring(selection.baseOffset + 1);
}
