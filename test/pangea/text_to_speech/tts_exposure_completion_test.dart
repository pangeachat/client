import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';
import 'package:fluffychat/features/analytics/listening_exposure_declaration.dart';
import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_tts_engine.dart';
import 'tts_test_harness.dart';

/// Exposure is minted only on a playback that ran to its END.
///
/// The trap this pins: "a route played" is NOT the same fact. Listening minutes
/// bank whatever played, because a learner who heard half a message did hear
/// that half — so `TtsDeviceOutcome.played` deliberately covers an utterance
/// that was cut off, and a Choreo `Loading interrupted` is reported as an
/// expected cancellation rather than a failure. Word-level exposure is
/// all-or-nothing per lemma: a read stopped after two words did not expose the
/// learner to the rest of the sentence. Gating exposure on the start signal, or
/// on either route's success return, over-records exactly there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('tts_exposure_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  const learner = '@learner:example.org';
  late FakeTtsEngine engine;

  ListeningExposureDeclaration hablar({String langCode = 'es'}) =>
      ListeningExposureDeclaration([
        ConstructIdentifier(
          lemma: 'hablar',
          type: ConstructTypeEnum.vocab,
          category: 'verb',
        ),
      ], langCode: langCode);

  int recordedExposures() =>
      ListeningExposureBuffer.forAccount(learner)?.pendingExposuresFor('es') ??
      0;

  Future<void> untilTrue(bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUpAll(() async {
    dotenv.testLoad(
      mergeWith: {
        'CHOREO_API': 'https://choreo.test',
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
    await GetStorage.init('env_override');
    await GetStorage.init('phonetic_transcription_v2');
  });

  setUp(() {
    DosageAudioBuffer.debugResetAccounts();
    ListeningExposureBuffer.debugResetAccounts();
    MatrixState.pangeaController = PlayablePangeaController();
    // Both voices from the start. `TtsController` derives its available-language
    // list from `getVoices` and caches it on a static that is only refreshed on
    // web, so a voice added later in the file is never seen — the French test
    // below would then pass because nothing played, not because nothing was
    // recorded.
    engine = FakeTtsEngine(
      voices: const [
        {'name': 'Paulina', 'locale': 'es-ES', 'quality': 'enhanced'},
        {'name': 'Amelie', 'locale': 'fr-FR', 'quality': 'enhanced'},
      ],
    )..install();
    TtsController.deviceStartTimeout = const Duration(milliseconds: 60);
    TtsController.stopSettleTimeout = const Duration(milliseconds: 60);
  });

  tearDown(() async {
    await TtsController.forceStop();
    engine.uninstall();
    TtsController.deviceStartTimeout = const Duration(seconds: 3);
    TtsController.stopSettleTimeout = const Duration(milliseconds: 300);
  });

  test('a device utterance that finishes records its lemmas', () async {
    engine.onSpeak = FakeSpeakBehavior.startAndComplete;

    await TtsController.tryToSpeak(
      'hablar',
      langCode: 'es',
      useCase: TtsUseCase.words,
      allowChoreoPlay: false,
      listening: SpyProbe(buffer: DosageAudioBuffer()),
      exposure: hablar(),
    );

    expect(
      recordedExposures(),
      1,
      reason: 'a clean finish is the case exposure exists for',
    );
  });

  test('an utterance cut off mid-read records nothing', () async {
    // The everyday case, not an edge one: read-aloud stops on drafting, on
    // selecting a message, and on losing focus, and every one of those routes
    // through the same stop. The engine still reports `played`, so without a
    // separate completion signal this banks the whole sentence.
    engine.onSpeak = FakeSpeakBehavior.startAndHang;
    final probe = SpyProbe(buffer: DosageAudioBuffer());

    final speaking = TtsController.tryToSpeak(
      'hablar',
      langCode: 'es',
      useCase: TtsUseCase.words,
      allowChoreoPlay: false,
      listening: probe,
      exposure: hablar(),
    );

    await untilTrue(() => engine.spoken.isNotEmpty);
    await TtsController.forceStop();
    await speaking;

    // Teeth. Without this the assertion below could pass because nothing
    // played at all, which is a different bug and not the one being pinned: a
    // route DID start, the minutes lane banks what it heard, and exposure
    // still must not.
    expect(probe.starts, greaterThan(0), reason: 'audio really did start');
    expect(probe.aborts, 0, reason: 'and was never reported as aborted');

    expect(
      recordedExposures(),
      0,
      reason: 'the learner never heard the rest of it',
    );
  });

  test('an utterance that never starts records nothing', () async {
    engine.onSpeak = FakeSpeakBehavior.errorBeforeStart;

    await TtsController.tryToSpeak(
      'hablar',
      langCode: 'es',
      useCase: TtsUseCase.words,
      allowChoreoPlay: false,
      listening: SpyProbe(buffer: DosageAudioBuffer()),
      exposure: hablar(),
    );

    expect(recordedExposures(), 0);
  });

  test('a superseded utterance records nothing', () async {
    // A newer request calls `_stop()` on the one in flight. That utterance is
    // still `played` — audio came out — but it was cut off, so its lemmas are
    // not exposure.
    engine.onSpeak = FakeSpeakBehavior.startAndHang;

    final first = TtsController.tryToSpeak(
      'hablar',
      langCode: 'es',
      useCase: TtsUseCase.words,
      allowChoreoPlay: false,
      listening: SpyProbe(buffer: DosageAudioBuffer()),
      exposure: hablar(),
    );
    await untilTrue(() => engine.spoken.isNotEmpty);

    engine.onSpeak = FakeSpeakBehavior.startAndComplete;
    await TtsController.tryToSpeak(
      'comer',
      langCode: 'es',
      useCase: TtsUseCase.words,
      allowChoreoPlay: false,
      listening: SpyProbe(buffer: DosageAudioBuffer()),
      exposure: const ListeningExposureDeclaration.exempt(
        'the second utterance is not what this test measures',
      ),
    );
    await first;

    expect(
      recordedExposures(),
      0,
      reason: 'the interrupted first read must not bank its lemma',
    );
  });

  test('a non-L2 utterance never reaches the L2 drain', () async {
    // The bug this pins: nothing in the exposure path used to look at language,
    // so a French word heard in a Spanish learner's room was filed as Spanish
    // vocabulary. Read-aloud is L2-gated, but voice messages and word taps in a
    // message are not — a multilingual room speaks whatever was written.
    engine.onSpeak = FakeSpeakBehavior.startAndComplete;

    await TtsController.tryToSpeak(
      'parler',
      langCode: 'fr',
      useCase: TtsUseCase.words,
      allowChoreoPlay: false,
      listening: SpyProbe(buffer: DosageAudioBuffer()),
      exposure: hablar(langCode: 'fr'),
    );

    final buffer = ListeningExposureBuffer.forAccount(learner)!;

    expect(
      buffer.drain('es'),
      isEmpty,
      reason: 'the Spanish room must not receive a French hearing',
    );
    expect(
      buffer.pendingExposuresFor('fr'),
      1,
      reason: 'and it is held under the language it was actually spoken in',
    );
  });

  test('an interruption we did not ask for records nothing', () async {
    // The everyday web case: Chrome cancels speechSynthesis and reports it as
    // an error. Nothing called our stop, so a rule of "ended and we did not
    // stop it" counts the whole utterance as heard.
    engine.onSpeak = FakeSpeakBehavior.startAndHang;
    final probe = SpyProbe(buffer: DosageAudioBuffer());

    final speaking = TtsController.tryToSpeak(
      'hablar',
      langCode: 'es',
      useCase: TtsUseCase.words,
      allowChoreoPlay: false,
      listening: probe,
      exposure: hablar(),
    );

    await untilTrue(() => engine.spoken.isNotEmpty);
    await engine.emit('speak.onError', 'interrupted');
    await speaking;

    expect(probe.starts, greaterThan(0), reason: 'audio really did start');
    expect(
      recordedExposures(),
      0,
      reason: 'nobody asked it to stop, and it still did not finish',
    );
  });

  test('an exempt path records nothing even on a clean finish', () async {
    engine.onSpeak = FakeSpeakBehavior.startAndComplete;

    await TtsController.tryToSpeak(
      'hablar',
      langCode: 'es',
      useCase: TtsUseCase.words,
      allowChoreoPlay: false,
      listening: SpyProbe(buffer: DosageAudioBuffer()),
      exposure: const ListeningExposureDeclaration.exempt('speaks no lemma'),
    );

    expect(recordedExposures(), 0);
  });
}
