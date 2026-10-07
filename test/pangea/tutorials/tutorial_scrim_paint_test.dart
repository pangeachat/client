import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_state_machine.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_widget.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The scrim darkens the screen by exactly [ThemeData.scrimOpacity] and leaves
/// the lit target untouched. The web bug that made it paint black (a
/// platform view in the scene) does not reproduce under `flutter test`; this
/// guards the painting itself.
void main() {
  const targetId = 'tutorial-scrim-target';

  setUpAll(() async => lookupL10n(const Locale('en')));

  testWidgets('darkens by scrimOpacity around the target, not inside it', (
    tester,
  ) async {
    final target = MatrixState.pAnyState.layerLinkAndKey(targetId);
    const boundaryKey = ValueKey('scrim-boundary');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 300,
                  child: SizedBox(key: target.key, width: 40, height: 40),
                ),
                TutorialOverlayWidget(
                  model: TutorialOverlayState(
                    activeTutorial: TutorialModel(
                      tutorialType: TutorialEnum.selectModeButtons,
                      stepsData: List.generate(
                        TutorialEnum.selectModeButtons.stepCount,
                        (_) => TutorialStepData.single(
                          targetKey: targetId,
                          canShowNextStep: () => true,
                        ),
                      ),
                    ),
                    stepIndex: 0,
                  ),
                  sequenceKind: TutorialSequenceKind.chat,
                  forward: () {},
                  reset: () {},
                  skipSequence: () {},
                  setTutorialTransitioning: (_) {},
                  completedSteps: 1,
                  totalSteps: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The overlay asks for a frame every frame, so pumpAndSettle never
    // settles: pump past the visibility flip, the measurement and the fade.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final boundary =
        tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
    final bytes = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    }))!;
    final width = boundary.size.width.toInt();
    int red(int x, int y) => bytes.getUint8((y * width + x) * 4);

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    final expected = (255 * (1 - theme.scrimOpacity)).round();
    expect(red(790, 590), closeTo(expected, 2), reason: 'the scrimmed screen');
    expect(red(120, 320), 255, reason: 'the lit target');
  });
}
