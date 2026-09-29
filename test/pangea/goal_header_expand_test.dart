import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goals_dropdown.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// #9318 — a goal clamped in the goal header (four lines collapsed, two in
/// the dropped-down list) can be read in full through an inline "Show more",
/// and a goal that fits offers no control at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Legacy goal lengths run well past the caps on a phone (#7971).
  final longGoal = List.filled(
    9,
    'compare the two countries in detail',
  ).join(' and ');
  const shortGoal = 'Say goodbye';

  setUpAll(() {
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() {
    MatrixState.pAnyState = PangeaAnyState();
  });

  Future<L10n> pump(WidgetTester tester, Widget child) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 900.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(mainAxisSize: MainAxisSize.min, children: [child]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return L10n.of(tester.element(find.byType(Scaffold)));
  }

  Widget collapsedHeader(String activeGoal) => ActivityGoalsDropdown(
    goals: [ActivityRoleGoal(id: 'g1', description: activeGoal)],
    completedGoalIds: const {},
    startCollapsed: true,
  );

  Finder inHeader(Finder matching) => find.descendant(
    of: find.byType(ActivityDropdownHeader),
    matching: matching,
  );

  testWidgets('a truncated active goal opens and closes in place', (
    tester,
  ) async {
    final l10n = await pump(tester, collapsedHeader(longGoal));

    expect(inHeader(find.textContaining(l10n.showMore)), findsOneWidget);
    expect(inHeader(find.textContaining(longGoal)), findsNothing);

    await tester.tapOnText(
      find.textRange.ofSubstring(
        l10n.showMore,
        descendentOf: find.byType(ActivityDropdownHeader),
      ),
    );
    await tester.pumpAndSettle();
    expect(inHeader(find.textContaining(longGoal)), findsOneWidget);
    expect(
      find.byType(ActivityDropdownContent).hitTestable(),
      findsNothing,
      reason: 'expanding the goal must not also open the goal list',
    );

    await tester.tapOnText(
      find.textRange.ofSubstring(
        l10n.showLess,
        descendentOf: find.byType(ActivityDropdownHeader),
      ),
    );
    await tester.pumpAndSettle();
    expect(inHeader(find.textContaining(longGoal)), findsNothing);
    expect(inHeader(find.textContaining(l10n.showMore)), findsOneWidget);
  });

  testWidgets('a goal that fits is plain text, not a button', (tester) async {
    final handle = tester.ensureSemantics();
    final l10n = await pump(tester, collapsedHeader(shortGoal));

    expect(inHeader(find.text(shortGoal)), findsOneWidget);
    expect(find.textContaining(l10n.showMore), findsNothing);
    final labelNode = tester.getSemantics(inHeader(find.text(shortGoal)));
    expect(labelNode.flagsCollection.isButton, isFalse);
    expect(
      labelNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    handle.dispose();
  });

  testWidgets(
    'on the list\'s top row, Show more expands the goal without collapsing '
    'the list, and the rest of the row still collapses it',
    (tester) async {
      var toggles = 0;
      final l10n = await pump(
        tester,
        ActivityDropdownContent(
          goals: [
            ActivityRoleGoal(id: 'g1', description: longGoal),
            const ActivityRoleGoal(id: 'g2', description: shortGoal),
          ],
          isGoalCompleted: (_) => false,
          onToggle: () => toggles++,
          activeGoalId: 'g1',
        ),
      );

      // Only the long goal gets a control; the short one fits.
      expect(find.textContaining(l10n.showMore), findsOneWidget);

      await tester.tapOnText(find.textRange.ofSubstring(l10n.showMore));
      await tester.pumpAndSettle();
      expect(find.textContaining(longGoal), findsOneWidget);
      expect(toggles, 0);

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      expect(toggles, 1);
    },
  );
}
