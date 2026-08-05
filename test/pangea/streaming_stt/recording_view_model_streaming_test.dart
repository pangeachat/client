import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/degradation_banner.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_repo.dart';
import 'package:fluffychat/routes/chat/recording_input_row.dart';
import 'package:fluffychat/routes/chat/recording_view_model.dart';

/// Mic-capture fake: never touches a real recorder.
class _FakeCapture implements SttAudioCaptureApi {
  bool started = false;
  bool stopped = false;

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
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    stopped = true;
  }
}

class _FakeWebSocketSink implements WebSocketSink {
  bool closed = false;
  final Completer<void> _done = Completer<void>();
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();

  bool get isClosed => _sink.closed;

  void emit(dynamic message) {
    if (!_incoming.isClosed) _incoming.add(message);
  }

  void emitError(Object error) {
    if (!_incoming.isClosed) _incoming.addError(error);
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready {
    // Model a compliant relay (B3): emit the wire-2 ready frame after the socket
    // handshake so the repo emits `open` and start() proceeds.
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
  int? get closeCode => _sink.closed ? 1000 : null;
  @override
  String? get closeReason => null;
}

/// No-op wakelock so the recorder's reset path (`WakelockPlus.disable()`) does
/// not hit a real platform channel in the widget test.
class _FakeWakelock extends WakelockPlusPlatformInterface
    with MockPlatformInterfaceMixin {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    WakelockPlusPlatformInterface.instance = _FakeWakelock();
    // isRecordingAnywhere is a process-wide static (main reads it to suppress
    // read-aloud while the mic is hot); reset it so a prior test cannot leak in.
    RecordingViewModelState.isRecordingAnywhere = false;
  });

  testWidgets(
    'pause() while streaming tears down the mic + socket (fix #1, D6)',
    (tester) async {
      final capture = _FakeCapture();
      final channel = _FakeWebSocketChannel();
      final repo = SttStreamRepo(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
        connector: (uri, {protocols}) => channel,
      );
      final session = StreamingSttSession(capture: capture, repo: repo);

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

      // Attach an already-started streaming session (bypasses the mic/wakelock
      // platform plugins that startRecording touches). start() awaits the
      // socket open handshake, so run it on the real clock via runAsync.
      await tester.runAsync(() => session.start());
      state.debugAttachStreamingSession(session);
      expect(capture.started, isTrue);

      // The BLOCKER: before the fix, pause() was a no-op while streaming and
      // left the mic + socket alive. pause() routes through cancel/_reset, which
      // fires the session teardown as an unawaited real-async future — drain it
      // with runAsync so capture.stop()/repo.close() actually complete.
      await tester.runAsync(() async {
        state.pause();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(capture.stopped, isTrue);
      expect(channel.isClosed, isTrue);
      expect(state.isStreaming, isFalse);
    },
  );

  testWidgets(
    'a live streaming start marks isRecordingAnywhere and _reset() clears it '
    '(read-aloud suppression parity with the batch path)',
    (tester) async {
      final capture = _FakeCapture();
      final channel = _FakeWebSocketChannel();
      final repo = SttStreamRepo(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
        connector: (uri, {protocols}) => channel,
      );
      final session = StreamingSttSession(capture: capture, repo: repo);

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

      // A live streaming start => the mic is hot. main reads this static in
      // ChatController.isSuppressed to silence device TTS that would otherwise
      // be captured + uploaded. The merge auto-placed main's `= true` on the
      // batch-only path; a live stream must set it too.
      await tester.runAsync(() => session.start());
      state.debugAttachStreamingSession(session);
      expect(capture.started, isTrue);
      expect(RecordingViewModelState.isRecordingAnywhere, isTrue);

      // Teeth on the merge resolution: our streaming teardown in _reset() must
      // STILL clear main's flag. pause() routes through cancel/_reset.
      await tester.runAsync(() async {
        state.pause();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(state.isStreaming, isFalse);
      expect(RecordingViewModelState.isRecordingAnywhere, isFalse);
    },
  );

  testWidgets(
    'streaming => ONE replace-in-place transcript line ABOVE the controls Row; '
    'batch => only the Row (#8 seam)',
    (tester) async {
      final capture = _FakeCapture();
      final channel = _FakeWebSocketChannel();
      final repo = SttStreamRepo(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
        connector: (uri, {protocols}) => channel,
      );
      final session = StreamingSttSession(capture: capture, repo: repo);

      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: RecordingViewModel(
              streamingSessionFactory: () => session,
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
      await tester.pumpAndSettle(); // L10n delegates load async.

      // BATCH (no streaming session attached): today's single controls Row,
      // no transcript line above it.
      expect(state.isStreaming, isFalse);
      expect(find.byIcon(Icons.send_outlined), findsOneWidget);
      expect(find.text('live one'), findsNothing);

      // Go STREAMING: attach the session and apply a partial (no socket needed
      // — debugApplyPartial drives the same _onPartial the relay would).
      state.debugAttachStreamingSession(session);
      session.debugApplyPartial(
        const SttPartial(
          transcript: 'live one',
          words: <SttWord>[],
          isFinal: false,
          speechFinal: false,
        ),
      );
      await tester.pump();

      expect(state.isStreaming, isTrue);
      // Exactly ONE read-only transcript line, rendered ABOVE the controls Row.
      expect(find.text('live one'), findsOneWidget);
      final lineDy = tester.getTopLeft(find.text('live one')).dy;
      final sendDy = tester.getTopLeft(find.byIcon(Icons.send_outlined)).dy;
      expect(
        lineDy,
        lessThan(sendDy),
        reason: 'the transcript line must sit above the controls Row',
      );

      // REPLACE-IN-PLACE: a newer partial replaces the line, never appends.
      session.debugApplyPartial(
        const SttPartial(
          transcript: 'live two',
          words: <SttWord>[],
          isFinal: false,
          speechFinal: false,
        ),
      );
      await tester.pump();
      expect(find.text('live one'), findsNothing);
      expect(find.text('live two'), findsOneWidget);

      // Stop the duration timer so no pending Timer trips the test teardown.
      state.cancel();
      await tester.pump();
    },
  );

  testWidgets(
    'dispose while streaming -> a late partial does not setState after dispose (#2)',
    (tester) async {
      final capture = _FakeCapture();
      final channel = _FakeWebSocketChannel();
      final repo = SttStreamRepo(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
        connector: (uri, {protocols}) => channel,
      );
      final session = StreamingSttSession(capture: capture, repo: repo);

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
      state.debugAttachStreamingSession(session);

      // Dispose the widget (real dispose: unmount).
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // A late partial arrives AFTER dispose. The session's onUpdate callback
      // (`if (mounted) setState`) must NOT setState on the defunct State.
      // (Reverting the `if (mounted)` guard => setState after dispose => throw
      // => takeException non-null => RED.)
      session.debugApplyPartial(
        const SttPartial(
          transcript: 'late-after-dispose',
          words: <SttWord>[],
          isFinal: false,
          speechFinal: false,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual send button waits for retained-WAV recovery then uses batch once',
    (tester) async {
      final capture = _FakeCapture();
      final channel = _FakeWebSocketChannel();
      final writeGate = Completer<void>();
      var writes = 0;
      final repo = SttStreamRepo(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
        connector: (uri, {protocols}) => channel,
      );
      final session = StreamingSttSession(
        capture: capture,
        repo: repo,
        tempFileWriter: (_) async {
          writes++;
          await writeGate.future;
          return '/tmp/retained.wav';
        },
      );

      late RecordingViewModelState state;
      Object? gotStreamed = Object();
      var sendCalled = false;
      String? sentPath;
      Future<void> onSend(
        String path,
        int duration,
        List<int> waveform,
        String? fileName, {
        StreamingSttSendData? streamedTranscript,
      }) async {
        sendCalled = true;
        gotStreamed = streamedTranscript;
        sentPath = path;
      }

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: RecordingViewModel(
            streamingSessionFactory: () => session,
            builder: (context, s) {
              state = s;
              return Scaffold(
                body: RecordingInputRow(state: s, onSend: onSend),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start + attach the session (start() awaits the ready->open handshake).
      await tester.runAsync(() => session.start());
      state.debugAttachStreamingSession(session);
      expect(capture.started, isTrue);

      session.debugOnFrame(
        Uint8List.fromList(<int>[0, 64, 0, 64, 0, 64, 0, 64]),
      );
      channel.emitError(Exception('relay unavailable'));
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final sendButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send_outlined),
      );
      expect(sendButton.onPressed, isNull);
      await tester.tap(find.byIcon(Icons.send_outlined));
      expect(sendCalled, isFalse);

      writeGate.complete();
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(state.isStreaming, isTrue);

      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      expect(sendCalled, isTrue);
      expect(sentPath, '/tmp/retained.wav');
      expect(gotStreamed, isNull);
      expect(writes, 1);
      expect(state.isStreaming, isFalse);
      expect(capture.stopped, isTrue);
      expect(channel.isClosed, isTrue);
    },
  );

  group('degradation banner (H9b live / B4 batch)', () {
    Future<
      ({
        RecordingViewModelState state,
        StreamingSttSession session,
        _FakeWebSocketChannel channel,
      })
    >
    mountStreaming(WidgetTester tester) async {
      final capture = _FakeCapture();
      final channel = _FakeWebSocketChannel();
      final repo = SttStreamRepo(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
        connector: (uri, {protocols}) => channel,
      );
      final session = StreamingSttSession(
        capture: capture,
        repo: repo,
        // A fast, disk-free temp writer: the batch-degrade test needs the
        // retained-WAV synth to settle without path_provider platform mocking.
        tempFileWriter: (_) async => '/tmp/banner_test_retained.wav',
      );

      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: RecordingViewModel(
              streamingSessionFactory: () => session,
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

      await tester.runAsync(() => session.start());
      state.debugAttachStreamingSession(session);
      await tester.pump();

      return (state: state, session: session, channel: channel);
    }

    testWidgets(
      'degraded=true (runner-up) renders the LIVE banner, not the batch one',
      (tester) async {
        final m = await mountStreaming(tester);

        expect(m.state.degradationBanner, DegradationBannerKind.none);

        m.channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'provider',
            'id': 'assemblyai',
            'degraded': true,
            'primary': 'deepgram',
          }),
        );
        await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(m.state.degradationBanner, DegradationBannerKind.degradedLive);

        m.state.cancel();
        await tester.pump();
      },
    );

    testWidgets(
      'terminal all_providers_down degrade renders the BATCH banner',
      (tester) async {
        final m = await mountStreaming(tester);

        m.session.debugOnFrame(
          Uint8List.fromList(<int>[0, 64, 0, 64, 0, 64, 0, 64]),
        );
        m.channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'error',
            'code': 'all_providers_down',
          }),
        );
        await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(
          m.state.degradationBanner,
          DegradationBannerKind.degradedToBatch,
        );

        m.state.cancel();
        await tester.pump();
      },
    );

    testWidgets(
      'a normal (non-degraded, primary-served) session shows NO banner',
      (tester) async {
        final m = await mountStreaming(tester);

        m.channel.emit(
          jsonEncode(<String, dynamic>{'type': 'provider', 'id': 'deepgram'}),
        );
        m.session.debugApplyPartial(
          const SttPartial(
            transcript: 'hello',
            words: <SttWord>[],
            isFinal: false,
            speechFinal: false,
          ),
        );
        await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(m.state.degradationBanner, DegradationBannerKind.none);

        m.state.cancel();
        await tester.pump();
      },
    );

    testWidgets('the X dismisses the currently shown banner', (tester) async {
      final m = await mountStreaming(tester);

      m.channel.emit(
        jsonEncode(<String, dynamic>{
          'type': 'provider',
          'id': 'assemblyai',
          'degraded': true,
          'primary': 'deepgram',
        }),
      );
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(m.state.degradationBanner, DegradationBannerKind.degradedLive);

      m.state.dismissDegradationBanner();
      await tester.pump();

      expect(m.state.degradationBanner, DegradationBannerKind.none);

      m.state.cancel();
      await tester.pump();
    });

    testWidgets(
      'a later, different degradation reason resurfaces even after the '
      'earlier one was dismissed',
      (tester) async {
        final m = await mountStreaming(tester);

        // Degrade to LIVE, then dismiss it.
        m.channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'provider',
            'id': 'assemblyai',
            'degraded': true,
            'primary': 'deepgram',
          }),
        );
        await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
        await tester.pump();
        m.state.dismissDegradationBanner();
        await tester.pump();
        expect(m.state.degradationBanner, DegradationBannerKind.none);

        // Then the whole chain fails (a strictly WORSE, DIFFERENT reason): the
        // banner must resurface despite the earlier dismissal.
        m.session.debugOnFrame(
          Uint8List.fromList(<int>[0, 64, 0, 64, 0, 64, 0, 64]),
        );
        m.channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'error',
            'code': 'all_providers_down',
          }),
        );
        await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(
          m.state.degradationBanner,
          DegradationBannerKind.degradedToBatch,
        );

        m.state.cancel();
        await tester.pump();
      },
    );
  });
}
