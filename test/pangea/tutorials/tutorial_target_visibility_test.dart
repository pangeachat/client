import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

const double _viewportHeight = 100.0;

/// A target hosted the way the start page hosts its join list: inside a
/// scroll view, with [above] pixels of content pushing it down a viewport
/// that is only [_viewportHeight] tall.
Widget _scrollHost(
  String targetId, {
  required double above,
  required double height,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 200.0,
        height: _viewportHeight,
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: above),
              TutorialTarget(
                targetId: targetId,
                child: SizedBox(width: 200.0, height: height),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

RenderBox _box(String targetId) =>
    MatrixState.pAnyState.getRenderBox(targetId)!;

Rect _viewport(WidgetTester tester) =>
    tester.getRect(find.byType(SingleChildScrollView));

Future<void> _ensureVisible(WidgetTester tester, String targetId) async {
  final done = TutorialTarget.ensureVisible(targetId);
  await tester.pumpAndSettle();
  await done;
}

void main() {
  group('TutorialTarget.visibleRect', () {
    testWidgets('cuts a target running past the fold to its viewport', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scrollHost('clip_partial', above: 50.0, height: 300.0),
      );
      final viewport = _viewport(tester);
      expect(
        TutorialTarget.visibleRect(_box('clip_partial')),
        Rect.fromLTRB(
          viewport.left,
          viewport.top + 50.0,
          viewport.right,
          viewport.bottom,
        ),
      );
    });

    testWidgets('a target scrolled entirely away collapses to a point on the '
        'viewport edge — still a rect, so the overlay does not read it as '
        'gone', (tester) async {
      await tester.pumpWidget(
        _scrollHost('clip_gone', above: 150.0, height: 30.0),
      );
      final viewport = _viewport(tester);
      final visible = TutorialTarget.visibleRect(_box('clip_gone'));
      expect(visible.isEmpty, isTrue);
      expect(visible.topLeft, viewport.bottomLeft);
    });

    testWidgets('a target with no viewport above it measures whole', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: TutorialTarget(
                targetId: 'clip_none',
                child: SizedBox(width: 120.0, height: 40.0),
              ),
            ),
          ),
        ),
      );
      expect(
        TutorialTarget.visibleRect(_box('clip_none')),
        tester.getRect(find.byType(TutorialTarget)),
      );
    });
  });

  group('TutorialTarget.ensureVisible', () {
    testWidgets('brings a target below the fold wholly on screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scrollHost('scroll_short', above: 150.0, height: 30.0),
      );
      expect(TutorialTarget.visibleRect(_box('scroll_short')).isEmpty, isTrue);

      await _ensureVisible(tester, 'scroll_short');

      final visible = TutorialTarget.visibleRect(_box('scroll_short'));
      expect(visible.height, 30.0);
      expect(visible.bottom, _viewport(tester).bottom);
    });

    testWidgets('a target taller than the viewport ends with its top edge '
        'showing — the slice the card anchors to', (tester) async {
      await tester.pumpWidget(
        _scrollHost('scroll_tall', above: 150.0, height: 300.0),
      );

      await _ensureVisible(tester, 'scroll_tall');

      expect(
        TutorialTarget.visibleRect(_box('scroll_tall')),
        _viewport(tester),
      );
    });

    testWidgets('is a no-op for an unregistered target', (tester) async {
      await tester.pumpWidget(
        _scrollHost('scroll_other', above: 150.0, height: 30.0),
      );
      await _ensureVisible(tester, 'scroll_missing');
      expect(TutorialTarget.visibleRect(_box('scroll_other')).isEmpty, isTrue);
    });
  });
}
