import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_exercise_widget.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_recorder.dart';
import 'package:fluffychat/routes/chat/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

class _FakeCapture implements SttAudioCaptureApi {
  bool started = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> start(
    void Function(Uint8List frame) onFrame, {
    void Function(Object error)? onError,
  }) async {
    started = true;
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

PangeaToken _token(String text, int offset) => PangeaToken(
  text: PangeaTokenText(content: text, offset: offset, length: text.length),
  lemma: Lemma(text: text.toLowerCase(), saveVocab: true, form: text),
  pos: 'NOUN',
  morph: const {},
);

/// "El gato come." with "gato" as the target.
ReadAloudPracticeExerciseModel _exercise() => ReadAloudPracticeExerciseModel(
  targetLemma: 'gato',
  exampleTokens: [
    _token('El', 0),
    _token('gato', 3),
    _token('come', 8),
    _token('.', 12),
  ],
  langCode: 'es',
  roomId: '!room',
  eventId: r'$evt',
  exampleMessage: const ExampleMessageInfo(
    exampleMessage: [TextSpan(text: 'El gato come.')],
  ),
);

/// The read-aloud item before any take: the sentence, the mic, and a Continue
/// that waits for an answer. See practice-exercises.instructions.md,
/// "Speaking practice".
void main() {
  testWidgets('renders the sentence, records on the mic tap, and holds '
      'Continue until the item is answered', (tester) async {
    final capture = _FakeCapture();
    List<String>? referenceGiven;
    var skipped = 0;
    final speed = AudioPlaybackSpeedController();
    addTearDown(speed.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ReadAloudExerciseWidget(
            exercise: _exercise(),
            referenceAudio: null,
            hearItFirst: true,
            playbackSpeedController: speed,
            recorderFactory: (reference) {
              referenceGiven = reference;
              return ReadAloudRecorder(
                reference: reference,
                hasMicPermission: () async => true,
                streamingSessionFactory: null,
                captureFactory: () => capture,
                transcribe: (_) async => const [],
              );
            },
            onRecorded: (_) {},
            onContinue: () {},
            onMicUnavailable: () {},
            onSkip: () => skipped++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The words to read are the sentence without its punctuation.
    expect(referenceGiven, ['El', 'gato', 'come']);
    expect(
      find.text('Tap the mic and read the sentence aloud'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byTooltip('Record'), findsOneWidget);

    final continueButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);

    // Skip is there from the start, not only after a failure.
    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    expect(skipped, 1);

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();

    expect(capture.started, isTrue);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byTooltip('Stop recording'), findsOneWidget);
  });
}
