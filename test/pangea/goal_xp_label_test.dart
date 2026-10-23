import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

/// The goal header's per-goal XP (#9559): an earned diamond shows its "+50"
/// under it, and an unearned one holds the same space empty so the row of
/// diamonds never shifts when a goal is earned.
void main() {
  Future<Size> pump(WidgetTester tester, {required bool complete}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: GoalStatusWidget(
              goal: const ActivityRoleGoal(id: 'g-0', description: 'Greet'),
              complete: complete,
              isActive: false,
              showLabel: false,
              goalXp: kGoalXp,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(GoalStatusWidget));
  }

  testWidgets('an earned goal shows its XP', (tester) async {
    await pump(tester, complete: true);
    expect(find.text('+$kGoalXp').hitTestable(), findsOneWidget);
  });

  testWidgets('an unearned goal holds the same space, empty', (tester) async {
    final earned = await pump(tester, complete: true);
    final unearned = await pump(tester, complete: false);
    // Held invisibly, so it is in the tree but not drawn or reachable.
    expect(find.text('+$kGoalXp').hitTestable(), findsNothing);
    expect(unearned, earned);
  });
}
