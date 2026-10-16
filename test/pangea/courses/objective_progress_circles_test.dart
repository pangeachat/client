import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_progress_circles.dart';

/// The Mission circles (#9420): a gold star for a complete Mission, the
/// current one tinted and numbered, the rest numbered; each carries its state
/// in its accessible name and its statement in its tooltip. The picked one is
/// pointed at, the class's place wears a "Class location" bubble, and a
/// Mission with a pinged open session wears a bell.
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

  Future<void> pump(
    WidgetTester tester, {
    void Function(int)? onTap,
    List<ObjectiveCircleData> items = items,
    bool showSelectedLabel = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ObjectiveProgressCircles(
            items: items,
            onTap: onTap,
            showSelectedLabel: showSelectedLabel,
          ),
        ),
      ),
    );
    // The localizations load asynchronously; nothing renders on the first frame.
    await tester.pumpAndSettle();
  }

  testWidgets('a complete Mission is a star, the others their number', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
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

  testWidgets('a screen reader can press a circle', (tester) async {
    final semantics = tester.ensureSemantics();
    int? tapped;
    await pump(tester, onTap: (i) => tapped = i);
    tester.semantics.tap(find.semantics.byLabel(RegExp('Mission 2: up next')));
    expect(tapped, 2);
    semantics.dispose();
  });

  testWidgets('the picked Mission is named under its pointer', (tester) async {
    await pump(
      tester,
      showSelectedLabel: true,
      items: [
        for (final item in items)
          ObjectiveCircleData(
            index: item.index,
            statement: item.statement,
            state: item.state,
            selected: item.index == 3,
          ),
      ],
    );
    expect(find.text('Mission 3'), findsOneWidget);
    expect(find.text('Mission 2'), findsNothing);
  });

  testWidgets('the class location and a ping are marked and announced', (
    tester,
  ) async {
    await pump(
      tester,
      items: const [
        ObjectiveCircleData(
          index: 1,
          statement: 'Can greet someone.',
          state: ObjectiveCircleState.current,
          classLocation: true,
        ),
        ObjectiveCircleData(
          index: 2,
          statement: 'Can introduce themselves.',
          state: ObjectiveCircleState.later,
          pinged: true,
        ),
      ],
    );
    expect(find.text('Class location'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Mission 1: up next, Class location')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Mission 2 of 2, Pinged')),
      findsOneWidget,
    );
  });
}
