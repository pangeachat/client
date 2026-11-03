import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_star_animation.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #9756 (CLIENT-BXD) — the chat moves the goal header to the next goal only
/// once the goal star calls onClose. A star the overlay holder refuses (a
/// tutorial is up, or the last star is still flying) never mounts, so it must
/// call onClose itself, or the header waits out the chat's 15 s timeout.
void main() {
  const starKey = 'goal-completion-star-test';
  const startTarget = 'goal_star_test_start';
  const endTarget = 'goal_star_test_end';

  setUp(() {
    // The overlay holder is a global static; give every test a clean one.
    MatrixState.pAnyState = PangeaAnyState();
  });

  /// A screen with the star's two targets on it, so a star that mounts flies.
  Future<BuildContext> pumpChat(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  key: MatrixState.pAnyState.layerLinkAndKey(endTarget).key,
                  width: 24,
                  height: 24,
                ),
                SizedBox(
                  key: MatrixState.pAnyState.layerLinkAndKey(startTarget).key,
                  width: 24,
                  height: 24,
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return context;
  }

  void showStar(BuildContext context, VoidCallback onClose) =>
      GoalStarAnimation.show(
        context,
        overlayKey: starKey,
        startTarget: startTarget,
        endTarget: endTarget,
        onClose: onClose,
      );

  testWidgets('a star refused behind a tutorial closes at once', (
    tester,
  ) async {
    final context = await pumpChat(tester);
    // The tutorial overlay is the entry that blocks every other.
    MatrixState.pAnyState.openOverlay(
      OverlayEntry(builder: (_) => const SizedBox()),
      context,
      canPop: false,
      blockOverlay: true,
    );

    var closes = 0;
    showStar(context, () => closes++);
    await tester.pump();

    expect(find.byType(GoalStarAnimation), findsNothing);
    expect(closes, 1);
  });

  testWidgets('a star refused while the last one flies closes at once', (
    tester,
  ) async {
    final context = await pumpChat(tester);

    var firstCloses = 0;
    var secondCloses = 0;
    showStar(context, () => firstCloses++);
    showStar(context, () => secondCloses++);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(GoalStarAnimation), findsOneWidget);
    expect(secondCloses, 1);
    expect(firstCloses, 0);

    // The star that did mount closes once, when its flight ends.
    await tester.pumpAndSettle();
    expect(find.byType(GoalStarAnimation), findsNothing);
    expect(firstCloses, 1);
    expect(secondCloses, 1);
  });
}
