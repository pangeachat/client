import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_content_widget.dart';
import 'package:fluffychat/routes/chat/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

/// #7719 follow-up — the device text scaler now reaches surfaces that used to
/// be pinned to `noScaling`, so every fixed-size box wrapped around one of them
/// has to grow with it. A box that stays put simply clips the text at large
/// device text sizes (accessibility.instructions.md, Text scaling).
///
/// The largest device setting is iOS's AX5, ~3.1x; 3.0 is used here as the
/// worst realistic case.
void main() {
  const maxDeviceScale = 3.0;

  Future<void> pumpAt(WidgetTester tester, double scale, Widget child) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: child),
          ),
        ),
      );

  group('word card height', () {
    testWidgets('grows with the device text scaler', (tester) async {
      late double atOne;
      late double atMax;

      await pumpAt(
        tester,
        1.0,
        Builder(
          builder: (context) {
            atOne = AppConfig.scaledToolbarMaxHeight(context);
            return const SizedBox();
          },
        ),
      );
      await pumpAt(
        tester,
        maxDeviceScale,
        Builder(
          builder: (context) {
            atMax = AppConfig.scaledToolbarMaxHeight(context);
            return const SizedBox();
          },
        ),
      );

      expect(atOne, AppConfig.toolbarMaxHeight);
      expect(
        atMax,
        AppConfig.toolbarMaxHeight * maxDeviceScale,
        reason:
            'the card is a fixed-height box of pure text; pinning it to 250 '
            'clips the word, its transcription and its meaning at large '
            'device text sizes',
      );
    });
  });

  group('analytics practice example-message slot', () {
    // The `_` branch of AnalyticsPracticeExerciseContent — a morph-match
    // exercise renders the example message into a fixed-height slot.
    MorphMatchPracticeExerciseModel exercise() =>
        MorphMatchPracticeExerciseModel(
          tokens: const [],
          langCode: 'es',
          morphFeature: MorphFeaturesEnum.Tense,
          multipleChoiceContent: MultipleChoicePracticeExercise(
            choices: {'Pres', 'Past'},
            answers: {'Pres'},
          ),
        );

    Future<double> slotHeight(WidgetTester tester, double scale) async {
      final controller = AudioPlaybackSpeedController();
      addTearDown(controller.dispose);

      await pumpAt(
        tester,
        scale,
        AnalyticsPracticeExerciseContent(
          analyticsPracticeExercise: exercise(),
          showHint: false,
          exampleMessage: Future.value(const <InlineSpan>[
            TextSpan(text: 'El perro bebe agua en el parque'),
          ]),
          playbackSpeedController: controller,
        ),
      );
      await tester.pump();

      return tester.getSize(find.byType(SizedBox).first).height;
    }

    testWidgets('grows with the device text scaler', (tester) async {
      final atOne = await slotHeight(tester, 1.0);
      final atMax = await slotHeight(tester, maxDeviceScale);

      expect(atOne, 100.0);
      expect(
        atMax,
        100.0 * maxDeviceScale,
        reason:
            'the example message inside scales with the device text size, so '
            'a fixed 100 clips the bubble',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
