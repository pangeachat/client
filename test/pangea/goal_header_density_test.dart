import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goals_dropdown.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// #9147 — the collapsed goal header floats over the conversation, so every
/// pixel it spends is a pixel of chat the learner can't see. On a phone with
/// the keyboard up that is most of what's left, so the narrow layout trims its
/// own padding — without letting the label close on the stars.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const narrowWidth = 390.0;
  const wideWidth = 1200.0;

  setUpAll(() {
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() {
    MatrixState.pAnyState = PangeaAnyState();
  });

  List<ActivityRoleGoal> goalsLedBy(String first) => [
    ActivityRoleGoal(id: 'g1', description: first),
    const ActivityRoleGoal(id: 'g2', description: 'Ask where they are from'),
    const ActivityRoleGoal(id: 'g3', description: 'Order a drink'),
    const ActivityRoleGoal(id: 'g4', description: 'Say goodbye'),
  ];

  /// Pumps the collapsed header at [width] logical pixels and returns the
  /// height the whole card costs the conversation.
  Future<double> pumpHeader(
    WidgetTester tester,
    double width,
    List<ActivityRoleGoal> goals,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 900.0);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: ThemeData(useMaterial3: true),
        // The Column leaves the height unbounded, as the live session's
        // `Positioned(bottom: null)` does, so the card shrink-wraps and its
        // measured height is what it actually costs the conversation.
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ActivityGoalsDropdown(
                goals: goals,
                completedGoalIds: const {},
                startCollapsed: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return tester.getSize(find.byType(ActivityGoalsDropdown)).height;
  }

  testWidgets('the narrow layout spends less height on the same header', (
    tester,
  ) async {
    // A label short enough to stay on one line at both widths, so the only
    // thing the two measurements differ by is the header's own padding.
    final goals = goalsLedBy('Greet');

    final wide = await pumpHeader(tester, wideWidth, goals);
    final narrow = await pumpHeader(tester, narrowWidth, goals);

    expect(
      narrow,
      lessThan(wide),
      reason: 'narrow ${narrow}px vs wide ${wide}px for an identical header',
    );
  });

  testWidgets('the goal label never closes on the stars', (tester) async {
    for (final width in [narrowWidth, wideWidth]) {
      const label = 'Greet the person sharing your table and ask their name';
      await pumpHeader(tester, width, goalsLedBy(label));

      final stars = tester.getRect(find.byType(GoalStatusWidget).first);
      final text = tester.getRect(
        find.descendant(
          of: find.byType(ActivityDropdownHeader),
          matching: find.text(label),
        ),
      );
      expect(
        text.top - stars.bottom,
        greaterThanOrEqualTo(8.0),
        reason:
            'stars and goal label are ${text.top - stars.bottom}px apart '
            'at ${width}px',
      );
    }
  });
}
