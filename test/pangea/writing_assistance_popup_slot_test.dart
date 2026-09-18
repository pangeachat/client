import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/igc/writing_assistance_popup_slot.dart';

/// #9074 — the span card and the suggestion card share one slot above the
/// input field, so they are measured by one rule instead of each carrying its
/// own hardcoded box.
void main() {
  test('the slot is as wide as the input field', () {
    final slot = WritingAssistancePopupSlot.above(
      inputWidth: 412.0,
      spaceAboveInput: 600.0,
    );

    expect(slot.maxWidth, 412.0);
  });

  test('the slot takes the space above the input, under the app bar', () {
    final slot = WritingAssistancePopupSlot.above(
      inputWidth: 412.0,
      spaceAboveInput: 600.0,
    );

    expect(slot.maxHeight, 600.0 - kToolbarHeight - 16.0);
  });

  test('a cramped chat still gets a usable slot', () {
    // On a short window the space above the input runs out; the card scrolls
    // its content rather than collapsing to a few unusable lines.
    final slot = WritingAssistancePopupSlot.above(
      inputWidth: 320.0,
      spaceAboveInput: 120.0,
    );

    expect(slot.maxHeight, 200.0);
  });

  test("the card's own height leaves room for the container's chrome", () {
    const slot = WritingAssistancePopupSlot(maxWidth: 412.0, maxHeight: 500.0);

    // OverlayContainer's 10px padding and 2px border, top and bottom.
    expect(slot.cardMaxHeight, 500.0 - 24.0);
  });
}
