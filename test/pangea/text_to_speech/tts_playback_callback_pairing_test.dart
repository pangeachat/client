import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

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
    );

    // A stranded id makes `stop` treat every later word as "not the current
    // request" and decline to stop it. `forceStop` is the unconditional path,
    // so reaching a cleared state is what proves the id was released.
    var stoppedLater = 0;
    await TtsController.tryToSpeak(
      'adios',
      langCode: 'es',
      useCase: TtsUseCase.words,
      onStop: () => stoppedLater++,
    );

    expect(stoppedLater, greaterThan(0));
  });
}
