import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

/// Asserts that exactly one semantics node carries [label] and that it is the
/// whole control — a button that is focusable and tappable — and that no
/// focusable node in the tree is nameless (#8873). Wrapping an InkWell in
/// `Semantics(excludeSemantics: true)` drops its focus semantics (a named
/// button with no `tabindex` on web); wrapping such a Semantics in an InkWell
/// leaves a roleless focusable node over the named one. Both look fine to a
/// sighted keyboard user and fail here.
void expectOneNodeControl(WidgetTester tester, String label) {
  final named = <SemanticsNode>[];
  final namelessFocusable = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    final focusable = node.flagsCollection.isFocused != Tristate.none;
    if (data.label == label) named.add(node);
    if (focusable && data.label.isEmpty) namelessFocusable.add(node);
  }
  expect(named, hasLength(1), reason: 'exactly one node named "$label"');
  final node = named.single;
  expect(node.flagsCollection.isButton, isTrue, reason: '"$label" is a button');
  expect(
    node.flagsCollection.isFocused,
    isNot(Tristate.none),
    reason: '"$label" is focusable (otherwise no tabindex on web)',
  );
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: '"$label" carries the tap action',
  );
  expect(
    namelessFocusable,
    isEmpty,
    reason: 'no nameless focusable node beside "$label"',
  );
}
