import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_tts_engine.dart';
import 'tts_test_harness.dart';

/// #8455: a device utterance always ends the request, and says how.
///
/// `_speakFromDevice` awaited the plugin's `speak` future, which with
/// `awaitSpeakCompletion(true)` resolves only when the engine reports the
/// utterance *finished*. It never resolves when the utterance errors — the web
/// plugin nulls its completer in `onError` without completing it, and Chrome
/// reports every interruption as an error — nor on iOS when a later `stop`
/// drops the pending result. So the request hung: its `finally` never ran, the
/// listening probe for a playback that DID start was never closed, its own
/// `onStop` never fired (the error handler called the PREVIOUS request's), and
/// `ReadAloudQueue`, which awaits `tryToSpeak`, stayed marked speaking.
///
/// These drive the real `tryToSpeak` against a scripted engine that answers the
/// method channel AND drives the plugin's callbacks back, the way each platform
/// does, so what is asserted is the whole path from tap to settled request.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('tts_device_failure');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  late FakeTtsEngine engine;

  /// A clock that advances a second per reading, so a playback that started
  /// measures a positive interval and a banked event is observable.
  DateTime Function() steppingClock() {
    var clock = DateTime.utc(2026, 1, 1, 12);
    return () {
      clock = clock.add(const Duration(seconds: 1));
      return clock;
    };
  }

  /// Poll until [ready] holds, so a test can drive a second tap while the
  /// first is mid-utterance without guessing at scheduling.
  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue, reason: 'condition never held');
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
    MatrixState.pangeaController = PlayablePangeaController();
    engine = FakeTtsEngine()..install();
    // Short, so a test of what the watchdog does is not a test of patience.
    TtsController.deviceStartTimeout = const Duration(milliseconds: 60);
    TtsController.stopSettleTimeout = const Duration(milliseconds: 60);
  });

  tearDown(() async {
    // Leave no utterance in flight for the next test's engine to inherit.
    await TtsController.forceStop();
    engine.uninstall();
    TtsController.deviceStartTimeout = const Duration(seconds: 3);
    TtsController.stopSettleTimeout = const Duration(milliseconds: 300);
  });

  group('an engine error before any start (web: not-allowed etc.)', () {
    test(
      'resolves the request, fires ITS OWN onStop, closes the probe',
      () async {
        engine.onSpeak = FakeSpeakBehavior.errorBeforeStart;
        final buffer = DosageAudioBuffer();
        final probe = SpyProbe(buffer: buffer, now: steppingClock());
        var stopped = 0;

        // Teeth: before #8455 this future never completed. The test would time
        // out rather than fail an assertion, so the fact that it returns is the
        // first thing pinned.
        await TtsController.tryToSpeak(
          'hola',
          langCode: 'es',
          useCase: TtsUseCase.words,
          allowChoreoPlay: false,
          listening: probe,
          onStop: () => stopped++,
        ).timeout(const Duration(seconds: 5));

        expect(engine.spoken, ['hola'], reason: 'the engine was asked');
        expect(
          stopped,
          greaterThan(0),
          reason: "the request's own onStop fired",
        );
        expect(probe.starts, 1, reason: 'the device route was asked to play');
        expect(probe.aborts, 1, reason: 'and it did not play');
        expect(probe.finishes, 1, reason: 'the measurement was closed');
        expect(buffer.bufferedEvents, isEmpty, reason: 'nothing was heard');
      },
    );

    test('is rescued by the backend for a subscribed user', () async {
      engine.onSpeak = FakeSpeakBehavior.errorBeforeStart;
      MatrixState.pangeaController = PlayablePangeaController(subscribed: true);
      final probe = SpyProbe(now: steppingClock());
      final backendCalls = <http.Request>[];

      await http.runWithClient(
        () => TtsController.tryToSpeak(
          'hola',
          langCode: 'es',
          useCase: TtsUseCase.words,
          listening: probe,
        ).timeout(const Duration(seconds: 5)),
        () => MockClient((request) async {
          backendCalls.add(request);
          // A failing backend keeps the test off `just_audio`; reaching it is
          // what is asserted here.
          return http.Response('{"detail":"nope"}', 502, request: request);
        }),
      );

      expect(engine.spoken, ['hola'], reason: 'device was tried first');
      expect(
        backendCalls.map((r) => r.url.path),
        contains(endsWith('/text_to_speech')),
        reason: 'the device failure was handed to the backend',
      );
      // Device: start/abort. Backend: failed before play, abort again. Nothing
      // was heard, and the failed device interval was dropped BEFORE the
      // rescue — not banked as the rescue's time.
      expect(probe.starts, 1);
      expect(probe.aborts, 2);
    });

    test('is NOT rescued when the request may not reach the backend', () async {
      // Setting-driven read-aloud: silence by design when the device cannot.
      engine.onSpeak = FakeSpeakBehavior.errorBeforeStart;
      MatrixState.pangeaController = PlayablePangeaController(subscribed: true);
      final backendCalls = <http.Request>[];

      await http.runWithClient(
        () => TtsController.tryToSpeak(
          'hola',
          langCode: 'es',
          useCase: TtsUseCase.newMessage,
          allowChoreoPlay: false,
          listening: SpyProbe(now: steppingClock()),
        ).timeout(const Duration(seconds: 5)),
        () => MockClient((request) async {
          backendCalls.add(request);
          return http.Response('{}', 200, request: request);
        }),
      );

      expect(backendCalls, isEmpty);
    });

    test('is NOT rescued for an unsubscribed user', () async {
      engine.onSpeak = FakeSpeakBehavior.errorBeforeStart;
      final backendCalls = <http.Request>[];

      await http.runWithClient(
        () => TtsController.tryToSpeak(
          'hola',
          langCode: 'es',
          useCase: TtsUseCase.words,
          listening: SpyProbe(now: steppingClock()),
        ).timeout(const Duration(seconds: 5)),
        () => MockClient((request) async {
          backendCalls.add(request);
          return http.Response('{}', 200, request: request);
        }),
      );

      expect(backendCalls, isEmpty);
    });
  });

  group('the next tap interrupts a word being spoken', () {
    for (final (platform, confirmation) in [
      ('Chrome: error(interrupted)', 'interrupted'),
      ('iOS: speak.onCancel', 'cancel'),
      ('browsers that fire end on cancel', 'end'),
    ]) {
      test(
        '$platform — the first request ends as heard, the second plays',
        () async {
          engine
            ..onSpeak = FakeSpeakBehavior.startAndHang
            ..stopConfirmation = confirmation;
          final bufferA = DosageAudioBuffer();
          final probeA = SpyProbe(buffer: bufferA, now: steppingClock());
          var aStopped = 0;

          final first = TtsController.tryToSpeak(
            'hola',
            langCode: 'es',
            useCase: TtsUseCase.words,
            allowChoreoPlay: false,
            listening: probeA,
            onStop: () => aStopped++,
          );
          // Mid-word: the engine has started and is hanging, as a real word
          // does until something ends it.
          await until(() => engine.log.contains('<-speak.onStart'));
          expect(aStopped, 0, reason: 'still speaking');

          engine.onSpeak = FakeSpeakBehavior.startAndComplete;
          final probeB = SpyProbe(
            buffer: DosageAudioBuffer(),
            now: steppingClock(),
          );
          await TtsController.tryToSpeak(
            'adios',
            langCode: 'es',
            useCase: TtsUseCase.words,
            allowChoreoPlay: false,
            listening: probeB,
          ).timeout(const Duration(seconds: 5));

          // Teeth: the first request's await never resolved before #8455, so
          // none of the following happened.
          await first.timeout(const Duration(seconds: 5));
          expect(aStopped, 1, reason: "the interrupted request's own onStop");
          expect(probeA.finishes, 1, reason: 'its measurement was closed');
          expect(probeA.aborts, 0, reason: 'it was heard, if cut short');
          expect(
            bufferA.bufferedEvents,
            hasLength(1),
            reason: 'what was heard before the cut is banked',
          );

          // And the second word actually spoke: issued only AFTER the engine
          // confirmed the first was stopped, so the web plugin — which drops a
          // `speak` while it still believes the previous one is playing — is
          // idle when it arrives.
          expect(engine.spoken, ['hola', 'adios']);
          final confirmed = engine.log.indexWhere(
            (e) => e.startsWith('<-speak.on') && e != '<-speak.onStart',
          );
          final secondSpeak = engine.log.lastIndexOf('speak');
          expect(confirmed, greaterThan(-1));
          expect(
            secondSpeak,
            greaterThan(confirmed),
            reason: 'second speak waited for the stop confirmation',
          );
          expect(probeB.starts, 1);
          expect(probeB.aborts, 0);
        },
      );
    }

    test(
      'an engine that never confirms the stop still frees both requests',
      () async {
        engine
          ..onSpeak = FakeSpeakBehavior.startAndHang
          ..stopFiresCancel = false;
        final probeA = SpyProbe(now: steppingClock());
        var aStopped = 0;

        final first = TtsController.tryToSpeak(
          'hola',
          langCode: 'es',
          useCase: TtsUseCase.words,
          allowChoreoPlay: false,
          listening: probeA,
          onStop: () => aStopped++,
        );
        await until(() => engine.log.contains('<-speak.onStart'));

        engine.onSpeak = FakeSpeakBehavior.startAndComplete;
        await TtsController.tryToSpeak(
          'adios',
          langCode: 'es',
          useCase: TtsUseCase.words,
          allowChoreoPlay: false,
          listening: SpyProbe(now: steppingClock()),
        ).timeout(const Duration(seconds: 5));

        // Settled on what was known once the wait for confirmation ran out:
        // it had started, so it was heard.
        await first.timeout(const Duration(seconds: 5));
        expect(aStopped, 1);
        expect(probeA.aborts, 0);
        expect(engine.spoken, ['hola', 'adios']);
      },
    );
  });

  group('the learner stops the word before it starts', () {
    test('cancelled: no rescue, nothing banked, onStop fires', () async {
      // The engine accepts the word but has not started when the stop lands.
      engine
        ..onSpeak = FakeSpeakBehavior.silentHang
        ..stopConfirmation = 'interrupted';
      MatrixState.pangeaController = PlayablePangeaController(subscribed: true);
      final buffer = DosageAudioBuffer();
      final probe = SpyProbe(buffer: buffer, now: steppingClock());
      final backendCalls = <http.Request>[];
      var stopped = 0;

      await http.runWithClient(
        () async {
          final request = TtsController.tryToSpeak(
            'hola',
            langCode: 'es',
            useCase: TtsUseCase.words,
            listening: probe,
            onStop: () => stopped++,
          );
          await until(() => engine.spoken.contains('hola'));
          await TtsController.stop(text: 'hola', langCode: 'es');
          await request.timeout(const Duration(seconds: 5));
        },
        () => MockClient((request) async {
          backendCalls.add(request);
          return http.Response('{}', 200, request: request);
        }),
      );

      expect(stopped, 1);
      expect(probe.aborts, 1, reason: 'nothing was heard');
      expect(buffer.bufferedEvents, isEmpty);
      expect(
        backendCalls,
        isEmpty,
        reason: 'silence was asked for; a stop is never rescued',
      );
    });
  });

  group('a plugin that never reports anything', () {
    test('the start watchdog ends the request as failed', () async {
      engine.onSpeak = FakeSpeakBehavior.silentHang;
      final probe = SpyProbe(now: steppingClock());
      var stopped = 0;

      final sw = Stopwatch()..start();
      await TtsController.tryToSpeak(
        'hola',
        langCode: 'es',
        useCase: TtsUseCase.words,
        allowChoreoPlay: false,
        listening: probe,
        onStop: () => stopped++,
      ).timeout(const Duration(seconds: 5));
      sw.stop();

      expect(stopped, 1);
      expect(probe.starts, 1);
      expect(probe.aborts, 1);
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'fails fast rather than hanging',
      );
      // The utterance it gave up on is told to stop, so it cannot start later
      // over whatever plays next.
      expect(
        engine.log.lastIndexOf('stop'),
        greaterThan(engine.log.indexOf('speak')),
      );
    });

    test(
      'a speak that returns without the engine starting is failed',
      () async {
        // A stale `end` from the previous utterance completing this one's speak
        // future, on browsers that fire `end` on cancel: nothing was spoken.
        engine.onSpeak = FakeSpeakBehavior.returnWithoutStart;
        MatrixState.pangeaController = PlayablePangeaController(
          subscribed: true,
        );
        final probe = SpyProbe(
          buffer: DosageAudioBuffer(),
          now: steppingClock(),
        );
        final backendCalls = <http.Request>[];

        await http.runWithClient(
          () => TtsController.tryToSpeak(
            'hola',
            langCode: 'es',
            useCase: TtsUseCase.words,
            listening: probe,
          ).timeout(const Duration(seconds: 5)),
          () => MockClient((request) async {
            backendCalls.add(request);
            return http.Response('{"detail":"nope"}', 502, request: request);
          }),
        );

        expect(probe.aborts, greaterThan(0), reason: 'not counted as heard');
        expect(backendCalls, isNotEmpty, reason: 'rescued');
      },
    );
  });
}
