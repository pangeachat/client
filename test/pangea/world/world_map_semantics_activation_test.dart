import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

/// Covers #7591: a control that names itself to assistive tech must also be
/// ACTIVATABLE through it. `Semantics(excludeSemantics: true)` drops the
/// descendant tree — including a wrapped GestureDetector/InkWell's implicit
/// tap action — so such nodes must carry their own `onTap`. These tests
/// perform the real [SemanticsAction.tap] (what a screen-reader double-tap
/// sends), not a pointer tap.
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Send the screen-reader activation to the node found by [label].
  void performSemanticsTap(WidgetTester tester, String label) {
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    tester.binding.rootPipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }

  for (final tier in [PinTier.small, PinTier.mid]) {
    testWidgets('a ${tier.name} pin activates via the semantics tap action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var tapped = false;
      await pump(
        tester,
        WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: tier,
          onTap: () => tapped = true,
          pinged: false,
        ),
      );

      performSemanticsTap(tester, 'Activity: Test Activity');
      expect(
        tapped,
        isTrue,
        reason:
            'a screen-reader double-tap on the ${tier.name} pin must open '
            'the activity (#7591)',
      );
      semantics.dispose();
    });
  }

  testWidgets('a cluster tracker activates via the semantics tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var tapped = false;
    await pump(
      tester,
      ClusterTrackerButton(
        indicator: ProgressIndicatorEnum.wordsUsed,
        count: 42,
        onTap: () => tapped = true,
      ),
    );

    final l10n = L10n.of(tester.element(find.byType(Scaffold)));
    performSemanticsTap(tester, '${l10n.vocab}: 42');
    expect(
      tapped,
      isTrue,
      reason:
          'a screen-reader double-tap on a tracker must open its analytics '
          'tab (#7591)',
    );
    semantics.dispose();
  });
}
