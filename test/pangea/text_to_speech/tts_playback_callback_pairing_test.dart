import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_listening_measurement.dart';
import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// A probe that records what `tryToSpeak` did to it.
///
/// The measurement's bracketing moved OUT of the call sites and INTO
/// `tryToSpeak` (#104), so "the caller remembered to close it" stopped being a
/// per-site property and became one guarantee to pin. This counts the three
/// transitions so the guarantee is asserted rather than assumed.
class _SpyProbe extends DosageTtsListeningProbe {
  _SpyProbe({super.buffer, super.now})
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

/// A controller complete enough for playback to actually REACH the device
/// route, rather than throwing in setup like [FakePangeaController] does.
///
/// Three things stand between `tryToSpeak` and a route that plays, and all
/// three read off the controller: the shared audio player it stops first, the
/// per-surface tool setting that gates the use case, and the subscription flag
/// the routing decision reads. A test that stops short of the route can only
/// ever assert what happens when nothing plays.
class _PlayablePangeaController implements PangeaController {
  @override
  final UserController userController = _EnabledUserController();

  @override
  final SubscriptionController subscriptionController =
      _UnsubscribedController();

  @override
  MatrixState get matrixState => _NoPlayerMatrixState();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _EnabledUserController implements UserController {
  @override
  bool isToolEnabled(ToolSetting setting) => true;

  @override
  String? get userL1Code => 'en';

  @override
  Completer<void> initCompleter = Completer<void>();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Unsubscribed on purpose. The device route is the one reachable without a
/// network, and staying off the paid route is what keeps this test hermetic.
class _UnsubscribedController implements SubscriptionController {
  @override
  bool get showSubscriptionGatedContent => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A shared audio player that is simply absent, which is what `tryToSpeak`
/// stopping it before every request has to tolerate.
class _NoPlayerMatrixState implements MatrixState {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_NoPlayerMatrixState';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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
    dotenv.testLoad(
      mergeWith: {
        'CHOREO_API': 'https://choreo.test',
        // The dosage lane is dark unless all three are set, and a dark buffer
        // records nothing — which would make the measurement assertions below
        // pass for the wrong reason.
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
    await GetStorage.init('env_override');
    await GetStorage.init('phonetic_transcription_v2');
  });

  setUp(() {
    // The per-account registry is app-global, so a buffer one test opened would
    // otherwise still be holding the next test's events.
    DosageAudioBuffer.debugResetAccounts();
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

    test('a route that ACTUALLY plays banks what was heard', () async {
      // The happy path, and the one worth the harness it takes. Every other
      // test here asserts what happens when nothing plays, so all of them would
      // still pass if `onPlaybackStarted` were dropped from the device and
      // backend route calls — and that regression undercounts every successful
      // read-aloud in the app while looking like a tidy cleanup.
      //
      // Reaching a route that plays needs a controller with a shared player, an
      // enabled tool setting and a subscription flag, plus a known-good device
      // voice for the language. `allowChoreoPlay: false` then forces the device
      // route, which is the only one reachable without a network.
      MatrixState.pangeaController = _PlayablePangeaController();
      // What the ENGINE was asked to do. Without it this test would still pass
      // for an implementation that reported a start and returned success
      // without speaking — which counts audio nobody heard, the same defect in
      // the opposite direction.
      final spoken = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ttsChannel, (call) async {
            if (call.method == 'getVoices') {
              return <Map<String, String>>[
                // `enhanced` ranks at the known-good threshold, which is what
                // lets a device-only request play at all.
                {'name': 'Paulina', 'locale': 'es-ES', 'quality': 'enhanced'},
              ];
            }
            if (call.method == 'speak') spoken.add('${call.arguments}');
            return 1;
          });

      final buffer = DosageAudioBuffer();
      // The mocked engine returns instantly, so a real clock measures zero and
      // banks nothing. This one advances a second per reading, which is what
      // makes a positive elapsed observable at all.
      var clock = DateTime.utc(2026, 1, 1, 12);
      final probe = _SpyProbe(
        buffer: buffer,
        now: () {
          clock = clock.add(const Duration(seconds: 1));
          return clock;
        },
      );

      await TtsController.tryToSpeak(
        'hola',
        langCode: 'es',
        useCase: TtsUseCase.newMessage,
        allowChoreoPlay: false,
        listening: DosageListeningMeasurement.measured(probe),
      );

      // The engine really was asked to speak, once, with this text. Everything
      // below only means "listening" if this holds.
      expect(spoken, ['hola'], reason: 'the device engine spoke the text once');

      expect(probe.starts, 1, reason: 'the device route was asked to play');
      expect(probe.aborts, 0, reason: 'and it did play');
      expect(probe.finishes, 1);

      // The teeth: an event, in the caller's category, actually reached the
      // buffer. Nothing short of the whole path being wired produces this.
      expect(buffer.bufferedEvents, hasLength(1));
      expect(
        buffer.bufferedEvents.single.category,
        DosageListeningCategory.autoRead,
      );
      expect(buffer.bufferedEvents.single.elapsedMs, greaterThan(0));
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
