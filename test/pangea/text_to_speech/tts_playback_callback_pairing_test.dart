import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_listening_measurement.dart';
import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// A probe that records what `tryToSpeak` did to it.
///
/// The measurement's bracketing moved OUT of the call sites and INTO
/// `tryToSpeak` (#104), so "the caller remembered to close it" stopped being a
/// per-site property and became one guarantee to pin. This counts the three
/// transitions so the guarantee is asserted rather than assumed.
class _SpyProbe extends DosageTtsListeningProbe {
  _SpyProbe({super.buffer})
    : super(
        category: DosageListeningCategory.autoRead,
        roomId: '!room:example.org',
        userId: () => '@learner:example.org',
        accessToken: () => 'syt_token',
      );

  int starts = 0;
  int aborts = 0;
  int finishes = 0;

  @override
  void started() {
    starts++;
    super.started();
  }

  @override
  void aborted() {
    aborts++;
    super.aborted();
  }

  @override
  void finish() {
    finishes++;
    super.finish();
  }
}

/// #8375, second half: a failed word-audio tap must not leave a stuck
/// indicator.
///
/// Audio affordances render their playing/loading state from the `onStart` /
/// `onStop` pair `tryToSpeak` hands them — `phonetic_transcription_widget`'s
/// `_playingId` is set in one and cleared in the other. `onStart` fires in
/// `tryToSpeak`, but `onStop` only fired on `_tryToSpeak`'s normal exits, so
/// anything throwing in between (a platform channel refusing `setLanguage`, the
/// shared audio player failing to stop) left the affordance marked as playing
/// forever, with the tap toggled into "stop" and no way back.
///
/// The same throw also stranded `_activeRequestId`, which makes
/// `TtsController.stop` decline to stop any later word ("Stop called with
/// different request than current").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The PT v2 phoneme cache is GetStorage-backed and its singleton builds on
  // first touch, so path_provider has to answer before `tryToSpeak` runs.
  final tempDir = Directory.systemTemp.createTempSync('tts_pairing_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  const ttsChannel = MethodChannel('flutter_tts');

  setUpAll(() async {
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('phonetic_transcription_v2');
  });

  setUp(() {
    // A stub controller with no Matrix state behind it: reaching for the shared
    // audio player throws, which is the in-between failure being pinned.
    MatrixState.pangeaController = FakePangeaController();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
          if (call.method == 'getVoices') return <Map<String, String>>[];
          return 1;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, null);
  });

  test(
    'onStart is always paired with onStop when playback setup throws',
    () async {
      var started = 0;
      var stopped = 0;

      await TtsController.tryToSpeak(
        'hola',
        langCode: 'es',
        useCase: TtsUseCase.words,
        listening: const DosageListeningMeasurement.notMeasured(
          DosageListeningExemption.awaitingCategory,
        ),
        onStart: () => started++,
        onStop: () => stopped++,
      );

      // Guards the test itself: if setup failed before `onStart`, the pairing
      // assertion below would pass vacuously.
      expect(
        started,
        greaterThan(0),
        reason: 'the affordance was marked playing',
      );

      // Teeth: without the guarantee, the throw skips `onStop` entirely and the
      // affordance stays marked as playing.
      expect(
        stopped,
        greaterThan(0),
        reason: 'a marked-playing affordance must always be cleared',
      );
    },
  );

  test('a throw does not strand the active request id', () async {
    await TtsController.tryToSpeak(
      'hola',
      langCode: 'es',
      useCase: TtsUseCase.words,
      listening: const DosageListeningMeasurement.notMeasured(
        DosageListeningExemption.awaitingCategory,
      ),
    );

    // A stranded id makes `stop` treat every later word as "not the current
    // request" and decline to stop it. `forceStop` is the unconditional path,
    // so reaching a cleared state is what proves the id was released.
    var stoppedLater = 0;
    await TtsController.tryToSpeak(
      'adios',
      langCode: 'es',
      useCase: TtsUseCase.words,
      listening: const DosageListeningMeasurement.notMeasured(
        DosageListeningExemption.awaitingCategory,
      ),
      onStop: () => stoppedLater++,
    );

    expect(stoppedLater, greaterThan(0));
  });

  group('tryToSpeak owns the measurement (#104)', () {
    test('it closes the measurement even when playback setup throws', () async {
      final probe = _SpyProbe();

      await TtsController.tryToSpeak(
        'hola',
        langCode: 'es',
        useCase: TtsUseCase.words,
        listening: DosageListeningMeasurement.measured(probe),
      );

      // The teeth. This harness has no Matrix state behind the controller, so
      // reaching the shared audio player throws part-way through setup — the
      // same in-between failure #8375 pinned for `onStop`. A measurement left
      // open by that throw keeps its meter running and books the NEXT playback's
      // wall clock as this one's. It is closed in a `finally`, so it cannot be.
      expect(
        probe.finishes,
        greaterThan(0),
        reason: 'a throw must still close the measurement',
      );
    });

    test('a setup that never played banks nothing', () async {
      final buffer = DosageAudioBuffer();
      final probe = _SpyProbe(buffer: buffer);

      await TtsController.tryToSpeak(
        'hola',
        langCode: 'es',
        useCase: TtsUseCase.words,
        listening: DosageListeningMeasurement.measured(probe),
      );

      // Closing a measurement is not the same as banking one. No route was ever
      // asked to play here, so `started` never fired and the interval was never
      // opened — the exact case that made timing the returned future unusable,
      // since this exit resolves in microseconds and would otherwise land a
      // near-zero playback for audio nobody heard.
      expect(probe.starts, 0, reason: 'no route was asked to play');
      expect(buffer.bufferedEvents, isEmpty);
    });

    test('an exempt call touches no measurement and still speaks', () async {
      var stopped = 0;

      await TtsController.tryToSpeak(
        'hola',
        langCode: 'es',
        useCase: TtsUseCase.words,
        listening: const DosageListeningMeasurement.notMeasured(
          DosageListeningExemption.awaitingRoomAndCategory,
        ),
        onStop: () => stopped++,
      );

      // The ten exempt call sites take this path on every tap. Nothing about
      // being unmeasured may change what the learner gets.
      expect(stopped, greaterThan(0));
    });
  });
}
