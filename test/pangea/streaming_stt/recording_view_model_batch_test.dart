import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/degradation_banner.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_repo.dart';
import 'package:fluffychat/routes/chat/recording_input_row.dart';
import 'package:fluffychat/routes/chat/recording_view_model.dart';
import '../get_test_client.dart';

/// A [RecordPlatform] test double: counts `start` (file recorder) vs
/// `startStream` (PCM streaming) so a test can prove which capture path ran and
/// with what codec — no real microphone.
class _FakeRecordPlatform extends RecordPlatform {
  int startCount = 0;
  int startStreamCount = 0;
  RecordConfig? lastStartConfig;
  String? lastStartPath;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId) async => true;

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    startCount++;
    lastStartConfig = config;
    lastStartPath = path;
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    startStreamCount++;
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -40, max: -30);

  @override
  Future<String?> stop(String recorderId) async => '/fake/recorded.wav';

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWakelock extends WakelockPlusPlatformInterface
    with MockPlatformInterfaceMixin {
  _FakeWakelock({this.enableFailures = 0});

  int enableFailures;
  int enableCount = 0;

  @override
  Future<void> toggle({required bool enable}) async {
    if (!enable) return;
    enableCount++;
    if (enableFailures > 0) {
      enableFailures--;
      throw StateError('wakelock unavailable');
    }
  }

  @override
  Future<bool> get enabled async => false;
}

/// A denied streaming socket: `ready` errors, so the session's connect never
/// opens and start() returns false (D10 -> batch fallback).
class _DeniedChannel extends StreamChannelMixin implements WebSocketChannel {
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  bool closed = false;

  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _DeniedSink(() => closed = true);
  @override
  Future<void> get ready =>
      Future<void>.error(Exception('1008 policy violation'));
  @override
  String? get protocol => null;
  @override
  int? get closeCode => closed ? 1000 : null;
  @override
  String? get closeReason => null;
}

class _DeniedSink implements WebSocketSink {
  _DeniedSink(this.onClose);
  final void Function() onClose;
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> close([int? closeCode, String? closeReason]) async => onClose();
  @override
  Future<void> get done => Future<void>.value();
}

class _FakeCapture implements SttAudioCaptureApi {
  _FakeCapture({this.startGate});

  /// Optional gate so a test can hold `start()` pending and interpose a
  /// cancel/dispose mid-flight.
  final Completer<void>? startGate;
  bool started = false;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> start(
    void Function(Uint8List frame) onFrame, {
    void Function(Object error)? onError,
  }) async {
    if (startGate != null) await startGate!.future;
    started = true;
    return true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    stopped = true;
  }
}

/// A streaming socket that opens normally and tracks its close.
class _OkChannel extends StreamChannelMixin implements WebSocketChannel {
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  bool closed = false;

  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _DeniedSink(() => closed = true);
  @override
  Future<void> get ready {
    // Model a compliant relay (B3): emit the wire-2 ready frame after the socket
    // handshake so the repo emits `open` and start() progresses to capture.start.
    scheduleMicrotask(() {
      if (!_incoming.isClosed) {
        _incoming.add(
          jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2}),
        );
      }
    });
    return Future<void>.value();
  }

  @override
  String? get protocol => null;
  @override
  int? get closeCode => closed ? 1000 : null;
  @override
  String? get closeReason => null;
}

void main() {
  late RecordPlatform originalRecord;
  late _FakeRecordPlatform record;
  late Client client;
  late Room room;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppSettings.init(loadWebConfigFile: false);

    final tempDir = await Directory.systemTemp.createTemp('rec_batch_test');
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );

    client = await getTestClient();
    room = Room(id: '!voice:fakeServer.notExisting', client: client);
  });

  setUp(() {
    originalRecord = RecordPlatform.instance;
    record = _FakeRecordPlatform();
    RecordPlatform.instance = record;
    final wakelock = _FakeWakelock();
    WakelockPlusPlatformInterface.instance = wakelock;
    wakelockPlusPlatformInstance = wakelock;
    // Process-wide static (main reads it to suppress read-aloud while the mic is
    // hot); reset so one test cannot leak the flag into the next.
    RecordingViewModelState.isRecordingAnywhere = false;
  });

  tearDown(() {
    RecordPlatform.instance = originalRecord;
  });

  Future<RecordingViewModelState> mountAndRecord(
    WidgetTester tester, {
    required StreamingSttSession Function()? factory,
  }) async {
    late RecordingViewModelState state;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingViewModel(
          streamingSessionFactory: factory,
          builder: (context, s) {
            state = s;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // startRecording (and, when present, the denied streaming attempt) awaits
    // real async — drive it on the real clock, then cancel to stop the recorder
    // duration timer inside the same zone so no timer outlives runAsync.
    await tester.runAsync(() async {
      await state.startRecording(room);
      state.cancel();
    });
    await tester.pump();
    return state;
  }

  testWidgets(
    'flag OFF: exactly ONE AudioRecorder started with AudioEncoder.wav, no streaming (#6)',
    (tester) async {
      final state = await mountAndRecord(tester, factory: null);

      // Byte-identical batch behaviour: one file recorder, NO PCM streaming, and
      // the EXACT today's RecordConfig (from AppSettings defaults). Any drift in
      // the flag-off recorder path fails here.
      expect(record.startCount, 1);
      expect(record.startStreamCount, 0);
      expect(state.isStreaming, isFalse);

      final cfg = record.lastStartConfig!;
      expect(cfg.encoder, AudioEncoder.wav);
      expect(cfg.sampleRate, 22050);
      expect(cfg.numChannels, 1);
      expect(cfg.bitRate, 64000);
      expect(cfg.autoGain, isTrue);
      expect(cfg.echoCancel, isFalse);
      expect(cfg.noiseSuppress, isTrue);
      expect(record.lastStartPath, endsWith('.wav'));
    },
  );

  testWidgets(
    'flag OFF: on-send hands the recorded wav path + .wav fileName through (#4)',
    (tester) async {
      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordingViewModel(
            streamingSessionFactory: null,
            builder: (context, s) {
              state = s;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      String? sentPath;
      List<int>? sentWaveform;
      String? sentFileName;
      StreamingSttSendData? sentStreamingTranscript;
      await tester.runAsync(() async {
        await state.startRecording(room);
        // Let the amplitude timer tick at least once so the send is not an
        // EmptyAudioException.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        state.stopAndSend((
          path,
          duration,
          waveform,
          fileName, {
          streamedTranscript,
        }) async {
          sentPath = path;
          sentWaveform = waveform;
          sentFileName = fileName;
          sentStreamingTranscript = streamedTranscript;
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      // Today's send path: the recorder's stop() file path + .wav fileName +
      // a non-empty waveform flow through onVoiceMessageSend unchanged.
      expect(record.startCount, 1);
      expect(sentPath, '/fake/recorded.wav');
      expect(sentFileName, endsWith('.wav'));
      expect(sentWaveform, isNotEmpty);
      expect(sentStreamingTranscript, isNull);
      expect(state.isEditingTranscript, isFalse);
    },
  );

  testWidgets(
    'flag ON but socket DENIED: falls back to the batch wav recorder (#5, D10)',
    (tester) async {
      final capture = _FakeCapture();
      final deniedChannel = _DeniedChannel();
      StreamingSttSession buildDenied() => StreamingSttSession(
        capture: capture,
        repo: SttStreamRepo(
          wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
          accessToken: 'TOKEN',
          connector: (uri, {protocols}) => deniedChannel,
        ),
      );

      final state = await mountAndRecord(tester, factory: buildDenied);

      // The denied streaming attempt did NOT strand the user: the recorder fell
      // through to today's batch wav path. (Reverting the await-open gate =>
      // the mic starts behind the dead socket and the batch recorder never
      // starts => startCount 0 => RED.)
      expect(record.startCount, 1);
      expect(record.startStreamCount, 0);
      expect(record.lastStartConfig?.encoder, AudioEncoder.wav);
      expect(state.isStreaming, isFalse);
      // The denied session was torn down: the mic never started behind the dead
      // socket and the socket was closed.
      expect(capture.started, isFalse);
      expect(deniedChannel.closed, isTrue);
    },
  );

  testWidgets(
    'wakelock failure after stream start tears it down and falls back to batch',
    (tester) async {
      final wakelock = _FakeWakelock(enableFailures: 1);
      WakelockPlusPlatformInterface.instance = wakelock;
      wakelockPlusPlatformInstance = wakelock;
      final capture = _FakeCapture();
      final channel = _OkChannel();
      final session = StreamingSttSession(
        capture: capture,
        repo: SttStreamRepo(
          wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
          accessToken: 'TOKEN',
          connector: (uri, {protocols}) => channel,
        ),
      );

      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordingViewModel(
            streamingSessionFactory: () => session,
            builder: (context, s) {
              state = s;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.runAsync(() async {
        await state.startRecording(room);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      expect(capture.started, isTrue);
      expect(capture.stopped, isTrue);
      expect(capture.disposed, isTrue);
      expect(channel.closed, isTrue);
      expect(record.startCount, 1);
      expect(wakelock.enableCount, 2);
      expect(state.isStreaming, isFalse);

      state.cancel();
    },
  );

  testWidgets(
    'PRODUCTION PATH: a successful live streaming start via startRecording sets '
    'isRecordingAnywhere (read-aloud suppression), and cancel/_reset clears it',
    (tester) async {
      final capture = _FakeCapture();
      final channel = _OkChannel();
      final session = StreamingSttSession(
        capture: capture,
        repo: SttStreamRepo(
          wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
          accessToken: 'TOKEN',
          connector: (uri, {protocols}) => channel,
        ),
      );

      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordingViewModel(
            streamingSessionFactory: () => session,
            builder: (context, s) {
              state = s;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(RecordingViewModelState.isRecordingAnywhere, isFalse);

      // Drive the REAL startRecording -> _startStreaming -> _StreamStartOutcome
      // .started path (NO debug seam). This is the teeth on the merge fix: if the
      // production `isRecordingAnywhere = true` on the streaming branch is
      // removed, main's read-aloud suppression breaks while live-streaming and
      // this expectation fails.
      await tester.runAsync(() async {
        await state.startRecording(room);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      expect(capture.started, isTrue);
      expect(state.isStreaming, isTrue);
      expect(RecordingViewModelState.isRecordingAnywhere, isTrue);

      // cancel routes through _reset(), which must clear the flag.
      await tester.runAsync(() async {
        state.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(state.isStreaming, isFalse);
      expect(RecordingViewModelState.isRecordingAnywhere, isFalse);
    },
  );

  testWidgets(
    'cancel during a PENDING streaming start -> NO batch recorder, no crash (#2/#5)',
    (tester) async {
      final startGate = Completer<void>();
      final capture = _FakeCapture(startGate: startGate);
      final channel = _OkChannel();
      final session = StreamingSttSession(
        capture: capture,
        repo: SttStreamRepo(
          wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
          accessToken: 'TOKEN',
          connector: (uri, {protocols}) => channel,
        ),
        connectTimeout: const Duration(milliseconds: 200),
      );

      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordingViewModel(
            streamingSessionFactory: () => session,
            builder: (context, s) {
              state = s;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // runAsync so the batch recorder's platform-channel awaits (path_provider)
      // actually resolve — otherwise a regression that DID reach batch would
      // silently stall and the test would be vacuous.
      await tester.runAsync(() async {
        unawaited(
          state.startRecording(room),
        ); // suspends in gated capture.start
        await Future<void>.delayed(const Duration(milliseconds: 40));
        state.cancel(); // user cancels DURING the pending streaming start
        startGate.complete(); // capture.start now resolves
        // Give a regression time to reach + start the batch recorder.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        // Stop any batch duration timer a regression would have started, so
        // runAsync can settle.
        state.cancel();
      });
      await tester.pump();

      // The aborted streaming start must NOT fall through to the batch recorder.
      // (Reverting the generation guard => `_startStreaming` returns "failed",
      // startRecording starts a batch AudioRecorder AFTER teardown =>
      // startCount 1 => RED.)
      expect(record.startCount, 0);
      expect(record.startStreamCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  // NOTE (dispose during a pending start): dispose() bumps the SAME start
  // generation cancel() does AND flips `mounted`, so `_startStreaming`/the batch
  // guard abort exactly as in the cancel case above (proven non-vacuous). The
  // dispose-specific "no setState after dispose" guarantee is exercised
  // directly in recording_view_model_streaming_test.dart
  // ("dispose while streaming -> a late partial does not setState after
  // dispose"), which can trigger a real widget dispose without the
  // runAsync/pumpWidget conflict a pending-start dispose test hits.

  group('language-unsupported degradation banner (D11, client-local)', () {
    testWidgets(
      'gate-rejected language shows the LANGUAGE-UNSUPPORTED banner at '
      'recording start — no streaming session ever attempted',
      (tester) async {
        late RecordingViewModelState state;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: RecordingViewModel(
                streamingSessionFactory: null,
                languageUnsupportedForStreaming: true,
                builder: (context, s) {
                  state = s;
                  return RecordingInputRow(
                    state: s,
                    onSend: (_, _, _, _, {streamedTranscript}) async {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() => state.startRecording(room));
        await tester.pump();

        // Byte-identical batch recorder underneath — the banner is additive.
        expect(record.startCount, 1);
        expect(record.startStreamCount, 0);
        expect(state.isStreaming, isFalse);
        expect(
          state.degradationBanner,
          DegradationBannerKind.languageUnsupported,
        );

        state.cancel();
        await tester.pump();
      },
    );

    testWidgets(
      'streaming simply not attempted for another reason (flag off / no '
      'token) shows NO banner — never mislabeled as the language reason',
      (tester) async {
        final state = await mountAndRecord(tester, factory: null);

        expect(state.degradationBanner, DegradationBannerKind.none);
      },
    );
  });

  testWidgets(
    'a send that lands AFTER the recorder unmounts does not setState on a '
    'defunct State (CLIENT-AN1)',
    (tester) async {
      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordingViewModel(
            streamingSessionFactory: null,
            builder: (context, s) {
              state = s;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final upload = Completer<void>();
      late Future<void> send;
      await tester.runAsync(() async {
        await state.startRecording(room);
        // Tick the amplitude timer so the send is not an EmptyAudioException.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        send = state.stopAndSend(
          (_, _, _, _, {streamedTranscript}) => upload.future,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      // The user leaves the chat while the upload is still in flight.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // stopAndSend still runs its trailing cancel() once the upload lands —
      // on a State that is no longer in the tree.
      Object? error;
      await tester.runAsync(() async {
        upload.complete();
        try {
          await send;
        } catch (e) {
          error = e;
        }
      });
      await tester.pump();

      expect(error, isNull);
    },
  );
}
