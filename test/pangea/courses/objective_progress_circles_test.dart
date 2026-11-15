import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_progress_circles.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section_scroll_arrow.dart';

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
    bool reserveClassLocation = false,
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
            reserveClassLocation: reserveClassLocation,
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
    expect(find.bySemanticsLabel(RegExp('Can-Do 1: complete')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Can-Do 2: up next')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Can-Do 3 of 3')), findsOneWidget);
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
    tester.semantics.tap(find.semantics.byLabel(RegExp('Can-Do 2: up next')));
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
    expect(find.text('Can-Do 3'), findsOneWidget);
    expect(find.text('Can-Do 2'), findsNothing);
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
      find.bySemanticsLabel(RegExp('Can-Do 1: up next, Class location')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Can-Do 2 of 2, Pinged')),
      findsOneWidget,
    );
  });

  // Twelve Missions at phone width: the row scrolls, with an arrow over each
  // end it can still move toward (#9602).
  group('a row wider than the screen', () {
    Future<void> pumpNarrow(
      WidgetTester tester, {
      required int selected,
      bool classLocation = true,
      bool bar = false,
    }) async {
      tester.view.physicalSize = const Size(360.0, 640.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        showSelectedLabel: bar,
        reserveClassLocation: bar,
        items: [
          for (var i = 1; i <= 12; i++)
            ObjectiveCircleData(
              index: i,
              statement: 'Mission $i.',
              state: ObjectiveCircleState.later,
              selected: i == selected,
              classLocation: classLocation && i == selected,
            ),
        ],
      );
    }

    Rect circle(WidgetTester tester, int index) => tester.getRect(
      find.ancestor(
        of: find.text('$index'),
        matching: find.byType(MissionXpRing),
      ),
    );

    Finder arrow(ArrowDirection direction) => find.byWidgetPredicate(
      (w) => w is ObjectiveSectionScrollArrow && w.direction == direction,
    );

    for (final (name, bar, classLocation) in [
      ('on the course page', false, false),
      ('on the course page with a class location', false, true),
      ('in the course bar', true, true),
    ]) {
      testWidgets(
        'an arrow covers the whole row, its chevron level with the circles, '
        '$name',
        (tester) async {
          await pumpNarrow(
            tester,
            selected: 9,
            bar: bar,
            classLocation: classLocation,
          );
          final row = tester.getRect(find.byType(ObjectiveProgressCircles));
          final circleCentre = circle(tester, 9).center.dy;
          for (final direction in ArrowDirection.values) {
            final strip = tester.getRect(arrow(direction));
            expect(strip.top, row.top, reason: 'over the class location');
            expect(strip.bottom, row.bottom, reason: 'over pointer and label');
            expect(
              tester.getCenter(find.byIcon(direction.icon)).dy,
              circleCentre,
            );
          }
        },
      );
    }

    // Mission 9 starts off the end; Mission 7 starts on screen, but where the
    // forward arrow sits.
    for (final selected in [7, 9]) {
      testWidgets('it opens with Mission $selected clear of the arrows', (
        tester,
      ) async {
        await pumpNarrow(tester, selected: selected, bar: true);
        final picked = circle(tester, selected);
        final row = tester.getRect(find.byType(ObjectiveProgressCircles));
        expect(picked.left, greaterThanOrEqualTo(row.left));
        expect(picked.right, lessThanOrEqualTo(row.right));
        for (final direction in ArrowDirection.values) {
          final strip = arrow(direction);
          if (strip.evaluate().isEmpty) continue;
          expect(picked.overlaps(tester.getRect(strip)), isFalse);
        }
      });
    }
  });
}
