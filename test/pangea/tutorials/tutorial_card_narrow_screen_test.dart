import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_state_machine.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_widget.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_tooltip_container_widget.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #9621 (CLIENT-F3G): the card's left edge is clamped between its side
/// padding and the far edge minus the card and that padding. A screen within
/// 16 px of the card's width inverted that range, and `clamp` threw on every
/// frame — a 300-wide card on a 320-wide phone rendered as an error box. Such
/// a card now centres; one wider than the screen keeps its left edge on it.
void main() {
  const targetId = 'tutorial-narrow-target';

  TutorialModel model(TutorialEnum type) => TutorialModel(
    tutorialType: type,
    stepsData: List.generate(
      type.stepCount,
      (_) => TutorialStepData.single(
        targetKey: targetId,
        canShowNextStep: () => true,
      ),
    ),
  );

  Widget harness(TutorialModel tutorial) {
    final target = MatrixState.pAnyState.layerLinkAndKey(targetId);
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 100,
              top: 300,
              child: CompositedTransformTarget(
                link: target.link,
                child: SizedBox(key: target.key, width: 40, height: 40),
              ),
            ),
            TutorialOverlayWidget(
              model: TutorialOverlayState(
                activeTutorial: tutorial,
                stepIndex: 0,
              ),
              sequenceKind: TutorialSequenceKind.chat,
              forward: () {},
              reset: () {},
              skipSequence: () {},
              setTutorialTransitioning: (_) {},
              completedSteps: 1,
              totalSteps: 1,
            ),
          ],
        ),
      ),
    );
  }

  /// The overlay asks for a frame every frame while it is up, so pumpAndSettle
  /// never settles: a fixed few frames cover the localizations, the
  /// visibility flip and the spotlight measurement.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// The writing-assistance card is 300 wide, 316 with its padding.
  Future<Rect> cardOnScreen(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(model(TutorialEnum.writingAssistance)));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    return tester.getRect(find.byType(TutorialTooltipContainerWidget));
  }

  testWidgets('a card within its padding of the screen width is centred', (
    tester,
  ) async {
    final card = await cardOnScreen(tester, 320);
    expect(card.left, 2);
    expect(card.right, lessThanOrEqualTo(320));
  });

  testWidgets('a card wider than the screen keeps its left edge on it', (
    tester,
  ) async {
    final card = await cardOnScreen(tester, 300);
    expect(card.left, 0);
  });

  testWidgets('a card with room for its padding is nudged in as before', (
    tester,
  ) async {
    // Centred on the target at x=120 the card would start at -38; the nudge
    // puts it at the padding.
    final card = await cardOnScreen(tester, 400);
    expect(card.left, 8);
  });
}
