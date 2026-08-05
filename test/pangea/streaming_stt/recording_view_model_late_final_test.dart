import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_repo.dart';
import 'package:fluffychat/routes/chat/recording_view_model.dart';

/// Mic fake with a manual frame pump (no real recorder).
class _FakeCapture implements SttAudioCaptureApi {
  void Function(Uint8List)? _onFrame;
  bool started = false;

  void pushFrame(Uint8List frame) => _onFrame?.call(frame);

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> start(
    void Function(Uint8List frame) onFrame, {
    void Function(Object error)? onError,
  }) async {
    _onFrame = onFrame;
    started = true;
    return true;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
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

  /// Emit a raw D4 frame down the REAL inbound stream (the repo parses it and
  /// forwards to whatever subscriptions are live) — so a test can prove a late
  /// frame is dropped because the session cancelled its subscription, not just
  /// because the VM never wired it.
  void emit(String data) => _incoming.add(data);

  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready {
    // Model a compliant relay (B3): emit the wire-2 ready frame after the socket
    // handshake so the repo emits `open` and start() proceeds.
    scheduleMicrotask(
      () => emit(jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2})),
    );
    return Future<void>.value();
  }

  @override
  String? get protocol => null;
  @override
  int? get closeCode => _sink.closed ? 1000 : null;
  @override
  String? get closeReason => null;
}

class _FakeWakelock extends WakelockPlusPlatformInterface
    with MockPlatformInterfaceMixin {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

void main() {
  final List<String> writtenPaths = <String>[];
  Future<String> tempWriter(Uint8List wav) async {
    final dir = await Directory.systemTemp.createTemp('stt_vm_latefinal');
    final file = File('${dir.path}/voice.wav');
    await file.writeAsBytes(wav);
    writtenPaths.add(file.path);
    return file.path;
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    WakelockPlusPlatformInterface.instance = _FakeWakelock();
  });

  tearDown(() async {
    for (final p in writtenPaths) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
    writtenPaths.clear();
  });

  testWidgets(
    'D7 late-final impossible-by-construction: after stopStreamingToEditable, a '
    'partial driven into the session does NOT reach the editable buffer',
    (tester) async {
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
        tempFileWriter: tempWriter,
        finalizeTimeout: const Duration(milliseconds: 40),
        frameWatchdogTimeout: const Duration(seconds: 30),
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

      // Start the streaming session (socket-open handshake on the real clock),
      // then attach it (bypasses the mic/wakelock plugins startRecording hits).
      await tester.runAsync(() => session.start());
      state.debugAttachStreamingSession(session);
      expect(capture.started, isTrue);

      // Real audio (non-silence) so the empty-audio guard passes, then settle a
      // final BEFORE stop.
      final loud = Uint8List.fromList(<int>[0, 64, 0, 64, 0, 64, 0, 64]);
      capture.pushFrame(loud);
      capture.pushFrame(loud);
      session.debugApplyPartial(
        const SttPartial(
          transcript: 'hola mundo',
          words: <SttWord>[],
          isFinal: true,
          speechFinal: false,
        ),
      );

      // Stop -> the bounded drain runs, subscriptions are cancelled, the socket
      // closes, and the settled final becomes the editable buffer.
      await tester.runAsync(() => state.stopStreamingToEditable());
      await tester.pump();

      expect(state.isEditingTranscript, isTrue);
      expect(state.editableController!.text, 'hola mundo');

      // A late final now driven through the REAL inbound socket stream must NOT
      // reach the editable buffer: stopAndSynthesize cancelled the session's
      // partial subscription during finalize, so the frame is dropped at the
      // source (not merely un-wired at the VM). Driving it via the channel (not
      // debugApplyPartial) is what proves the subscription is actually gone.
      await tester.runAsync(() async {
        channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'stream_final',
            'transcript': 'LATE ASR OVERWRITE',
            'words': <Map<String, dynamic>>[],
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();

      expect(
        state.editableController!.text,
        'hola mundo',
        reason: 'a late final must never reach / clobber the editable buffer',
      );
      // And the session's own transcript is unchanged — the cancelled
      // subscription never delivered the late frame.
      expect(session.liveTranscript, isNot(contains('LATE ASR OVERWRITE')));

      state.cancel();
      await tester.pump();
    },
  );

  testWidgets(
    'D7 double-tap guard: two overlapping stopStreamingToEditable calls run the '
    'finalize+synthesis ONCE (no concurrent continuation, no leaked buffer)',
    (tester) async {
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
        tempFileWriter: tempWriter,
        finalizeTimeout: const Duration(milliseconds: 40),
        frameWatchdogTimeout: const Duration(seconds: 30),
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

      await tester.runAsync(() => session.start());
      state.debugAttachStreamingSession(session);

      final loud = Uint8List.fromList(<int>[0, 64, 0, 64, 0, 64, 0, 64]);
      capture.pushFrame(loud);
      capture.pushFrame(loud);
      session.debugApplyPartial(
        const SttPartial(
          transcript: 'hola mundo',
          words: <SttWord>[],
          isFinal: true,
          speechFinal: false,
        ),
      );

      // Fire the stop TWICE without awaiting the first. The first call sets the
      // `_finalizingToEditable` guard synchronously (before its first await), so
      // the second must early-return. Pre-fix (guard removed) BOTH pass the
      // `_editable == null` check across the drain await and each run a full
      // stopAndSynthesize -> two WAV writes + an overwritten (leaked) buffer.
      await tester.runAsync(() async {
        final f1 = state.stopStreamingToEditable();
        final f2 = state.stopStreamingToEditable();
        await Future.wait([f1, f2]);
      });
      await tester.pump();

      expect(
        writtenPaths.length,
        1,
        reason:
            'the finalize+WAV synthesis must run exactly once for a '
            'double-tap; a second continuation means the guard is gone',
      );
      expect(state.isEditingTranscript, isTrue);
      expect(state.isFinalizingToEditable, isFalse);
      expect(state.editableController!.text, 'hola mundo');

      state.cancel();
      await tester.pump();
    },
  );

  testWidgets(
    'D7 stop-race: a CANCEL during the finalizing drain invalidates the '
    'continuation — no cancelled session reappears as an editable buffer',
    (tester) async {
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
        tempFileWriter: tempWriter,
        finalizeTimeout: const Duration(milliseconds: 40),
        frameWatchdogTimeout: const Duration(seconds: 30),
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

      await tester.runAsync(() => session.start());
      state.debugAttachStreamingSession(session);

      final loud = Uint8List.fromList(<int>[0, 64, 0, 64, 0, 64, 0, 64]);
      capture.pushFrame(loud);
      capture.pushFrame(loud);
      session.debugApplyPartial(
        const SttPartial(
          transcript: 'hola mundo',
          words: <SttWord>[],
          isFinal: true,
          speechFinal: false,
        ),
      );

      // Begin the stop (suspends inside stopAndSynthesize's drain), then CANCEL
      // while it is in flight, then let the stop resume. cancel() bumps the
      // generation + nulls _streaming, so the resumed continuation must bail.
      await tester.runAsync(() async {
        final stop = state.stopStreamingToEditable();
        state.cancel();
        await stop;
      });
      await tester.pump();

      // Teeth: pre-fix (only a `mounted` check) the continuation reinstalled the
      // cancelled session as an editable buffer -> isEditingTranscript true.
      expect(state.isEditingTranscript, isFalse);
      expect(state.isFinalizingToEditable, isFalse);
      expect(state.editableController, isNull);
    },
  );

  testWidgets(
    'D7 send-race: a double-tap send calls onSend exactly ONCE (in-method '
    'isSending re-entrancy guard, not just UI disabling)',
    (tester) async {
      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordingViewModel(
            builder: (context, s) {
              state = s;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Enter the editable state directly with a retained result.
      state.debugEnterEditable(
        'hola mundo',
        result: StreamingSttResult(
          wavPath: '/tmp/voice.wav',
          transcript: 'hola mundo',
          duration: const Duration(seconds: 1),
        ),
      );
      await tester.pump();

      final gate = Completer<void>();
      var sends = 0;
      Future<void> onSend(
        String a,
        int b,
        List<int> c,
        String? d, {
        StreamingSttSendData? streamedTranscript,
      }) async {
        sends++;
        await gate.future;
      }

      final f1 = state.sendEditedTranscript(onSend);
      final f2 = state.sendEditedTranscript(onSend);
      // f1 is mid-send (awaiting the gate); f2 must have early-returned.
      expect(
        sends,
        1,
        reason:
            'the second send must be guarded out before calling onSend; '
            'removing `if (isSending) return` double-sends the same WAV',
      );

      gate.complete();
      await f1;
      await f2;
      expect(sends, 1);

      await tester.pump();
    },
  );

  testWidgets(
    'D8 language drift: the streamed send carries the RECORDING-time gated lang '
    '(session.lang), never a send-time value',
    (tester) async {
      final capture = _FakeCapture();
      final channel = _FakeWebSocketChannel();
      // Relay opened with a DISTINCT gated language ("es") so the assertion
      // proves the value flows from the session, not a hardcoded/send-time "en".
      final repo = SttStreamRepo(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
        lang: 'es',
        connector: (uri, {protocols}) => channel,
      );
      final session = StreamingSttSession(
        capture: capture,
        repo: repo,
        tempFileWriter: tempWriter,
        finalizeTimeout: const Duration(milliseconds: 40),
        frameWatchdogTimeout: const Duration(seconds: 30),
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

      await tester.runAsync(() => session.start());
      state.debugAttachStreamingSession(session);
      final loud = Uint8List.fromList(<int>[0, 64, 0, 64, 0, 64, 0, 64]);
      capture.pushFrame(loud);
      capture.pushFrame(loud);
      session.debugApplyPartial(
        const SttPartial(
          transcript: 'hola mundo',
          words: <SttWord>[],
          isFinal: true,
          speechFinal: false,
        ),
      );
      await tester.runAsync(() => state.stopStreamingToEditable());
      await tester.pump();

      StreamingSttSendData? captured;
      Future<void> onSend(
        String path,
        int duration,
        List<int> waveform,
        String? fileName, {
        StreamingSttSendData? streamedTranscript,
      }) async {
        captured = streamedTranscript;
      }

      await state.sendEditedTranscript(onSend);
      await tester.pump();

      // Teeth: pre-fix the editable buffer got no langCode (default ''), so the
      // send stamped the send-time L2 in onVoiceMessageSend — drift. It must be
      // the recording-time session lang.
      expect(captured, isNotNull);
      expect(captured!.langCode, 'es');
    },
  );
}
