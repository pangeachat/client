import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_content_widget.dart';
import 'package:fluffychat/routes/chat/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/utils/text_scaler_extension.dart';

/// Stands in for the system scaler on Android 14+, where scaling is a curve
/// rather than one multiplier: small text grows more than large text, so no
/// single factor describes it and `scale(x)` is not `x * factor`.
class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler();

  static const double smallFactor = 3.0;
  static const double largeFactor = 1.5;
  static const double threshold = 20.0;

  @override
  double scale(double fontSize) =>
      fontSize * (fontSize <= threshold ? smallFactor : largeFactor);

  @override
  double get textScaleFactor => smallFactor;
}

/// #7719 follow-up — the device text scaler now reaches surfaces that used to
/// be pinned to `noScaling`, so every fixed-size box wrapped around one of them
/// has to grow with it. A box that stays put simply clips the text at large
/// device text sizes (accessibility.instructions.md, Text scaling).
///
/// The largest device setting is iOS's AX5, ~3.1x; 3.0 is used here as the
/// worst realistic case.
void main() {
  const maxDeviceScale = 3.0;

  Future<void> pumpWith(WidgetTester tester, TextScaler scaler, Widget child) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: scaler),
            child: Scaffold(body: child),
          ),
        ),
      );

  Future<void> pumpAt(WidgetTester tester, double scale, Widget child) =>
      pumpWith(tester, TextScaler.linear(scale), child);

  group('TextScaler.factorAt', () {
    test('is the plain factor for a linear scaler', () {
      expect(TextScaler.linear(2.5).factorAt(16.0), 2.5);
      expect(TextScaler.linear(2.5).factorAt(28.0), 2.5);
      expect(TextScaler.noScaling.factorAt(16.0), 1.0);
    });

    test('reads a non-linear scaler at the font size asked for', () {
      const scaler = _NonLinearTextScaler();

      expect(scaler.factorAt(16.0), _NonLinearTextScaler.smallFactor);
      expect(scaler.factorAt(28.0), _NonLinearTextScaler.largeFactor);
    });

    test('a raw dimension fed to scale() answers for the wrong size', () {
      const scaler = _NonLinearTextScaler();

      // The mistake this replaces: a 250px box asked as if it were a 250pt
      // font lands on the far end of the curve, and grows by the factor large
      // text gets rather than the one its 16pt contents get.
      expect(scaler.scale(250.0), 250.0 * _NonLinearTextScaler.largeFactor);
      expect(
        250.0 * scaler.factorAt(AppConfig.messageFontSize),
        250.0 * _NonLinearTextScaler.smallFactor,
      );
    });
  });

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

    testWidgets('follows a non-linear scaler at its text size', (tester) async {
      late double height;

      await pumpWith(
        tester,
        const _NonLinearTextScaler(),
        Builder(
          builder: (context) {
            height = AppConfig.scaledToolbarMaxHeight(context);
            return const SizedBox();
          },
        ),
      );

      expect(
        height,
        AppConfig.toolbarMaxHeight * _NonLinearTextScaler.smallFactor,
        reason:
            'the box has to grow the way its 16pt contents grow; handing 250 '
            'to scale() reads the curve at a font size the card never renders',
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

    Future<double> slotHeight(WidgetTester tester, TextScaler scaler) async {
      final controller = AudioPlaybackSpeedController();
      addTearDown(controller.dispose);

      await pumpWith(
        tester,
        scaler,
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
      final atOne = await slotHeight(tester, TextScaler.linear(1.0));
      final atMax = await slotHeight(tester, TextScaler.linear(maxDeviceScale));

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

    testWidgets('follows a non-linear scaler at its text size', (tester) async {
      final height = await slotHeight(tester, const _NonLinearTextScaler());

      expect(
        height,
        100.0 * _NonLinearTextScaler.smallFactor,
        reason:
            'the slot tracks the message text inside it, not what the curve '
            'would do to a 100pt font',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
