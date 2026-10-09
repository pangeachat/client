import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_progress_circles.dart';

/// The Mission circles (#9420): a check for a complete Mission, the current
/// one ringed and numbered, the rest numbered; each carries its state in its
/// accessible name and its statement in its tooltip.
void main() {
  const items = [
    ObjectiveCircleData(
      index: 1,
      statement: 'Can greet someone.',
      state: ObjectiveCircleState.complete,
    ),
    ObjectiveCircleData(
      index: 2,
      statement: 'Can introduce themselves.',
      state: ObjectiveCircleState.current,
    ),
    ObjectiveCircleData(
      index: 3,
      statement: 'Can order a coffee.',
      state: ObjectiveCircleState.later,
    ),
  ];

  Future<void> pump(WidgetTester tester, {void Function(int)? onTap}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ObjectiveProgressCircles(items: items, onTap: onTap),
        ),
      ),
    );
    // The localizations load asynchronously; nothing renders on the first frame.
    await tester.pumpAndSettle();
  }

  testWidgets('a complete Mission is a check, the others their number', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('each circle names its state and carries its statement', (
    tester,
  ) async {
    await pump(tester);
    expect(
      find.bySemanticsLabel(RegExp('Mission 1: complete')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Mission 2: up next')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Mission 3 of 3')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Can order a coffee.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a circle reports its index', (tester) async {
    int? tapped;
    await pump(tester, onTap: (i) => tapped = i);
    await tester.tap(find.text('3'));
    expect(tapped, 3);
  });
}
