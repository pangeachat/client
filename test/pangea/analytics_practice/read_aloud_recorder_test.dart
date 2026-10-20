import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_recorder.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_repo.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_state.dart';

class _FakeCapture implements SttAudioCaptureApi {
  void Function(Uint8List)? _onFrame;
  bool disposed = false;

  void pushFrame(Uint8List frame) => _onFrame?.call(frame);

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> start(
    void Function(Uint8List frame) onFrame, {
    void Function(Object error)? onError,
  }) async {
    _onFrame = onFrame;
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeRepo extends SttStreamRepo {
  _FakeRepo()
    : super(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
      );

  final StreamController<SttStreamState> _stateCtrl =
      StreamController<SttStreamState>.broadcast();
  final StreamController<SttPartial> _partialCtrl =
      StreamController<SttPartial>.broadcast();

  @override
  Stream<SttStreamState> get state => _stateCtrl.stream;
  @override
  Stream<SttPartial> get partials => _partialCtrl.stream;

  void emitState(SttStreamState s) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  @override
  void connect() {}
  @override
  void sendAudio(Uint8List pcm) {}
  @override
  void stop() {}
  @override
  Future<void> close() async {
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
    if (!_partialCtrl.isClosed) await _partialCtrl.close();
  }
}

Future<String> _memWriter(Uint8List wav) async => '/tmp/read_aloud.wav';

const _reference = ['El', 'gato', 'come'];

void main() {
  group('ReadAloudRecorder on the streaming route', () {
    late _FakeRepo repo;
    late _FakeCapture capture;
    late StreamingSttSession session;
    late ReadAloudRecorder recorder;

    setUp(() {
      repo = _FakeRepo();
      capture = _FakeCapture();
      session = StreamingSttSession(
        capture: capture,
        repo: repo,
        tempFileWriter: _memWriter,
        finalizeTimeout: const Duration(milliseconds: 20),
      );
      recorder = ReadAloudRecorder(
        reference: _reference,
        hasMicPermission: () async => true,
        streamingSessionFactory: () => session,
        captureFactory: () => throw StateError('batch capture not expected'),
        transcribe: (_) async => throw StateError('batch not expected'),
      );
    });

    tearDown(() => recorder.dispose());

    Future<void> startLive() async {
      final starting = recorder.start();
      await pumpEventQueue();
      repo.emitState(SttStreamState.open);
      await starting;
      await pumpEventQueue();
    }

    test('words fill in as partials settle them, in order', () async {
      await startLive();
      expect(recorder.phase, ReadAloudPhase.recording);

      session.debugApplyPartial(
        const SttPartial(
          transcript: 'el gato',
          words: [],
          isFinal: false,
          speechFinal: false,
        ),
      );
      expect(recorder.heard, [true, true, false]);
    });

    test('every word heard ends the take by itself and judges it', () async {
      await startLive();
      capture.pushFrame(Uint8List(3200));
      session.debugApplyPartial(
        const SttPartial(
          transcript: 'El gato come.',
          words: [],
          isFinal: true,
          speechFinal: true,
        ),
      );
      await pumpEventQueue();
      // The finalizing drain is bounded by finalizeTimeout.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await pumpEventQueue();

      expect(recorder.phase, ReadAloudPhase.done);
      expect(recorder.allHeard, isTrue);
      expect(recorder.triesUsed, 1);
      expect(recorder.lastTake!.transcript, 'El gato come.');
      expect(recorder.lastTake!.wav, isNotNull);
    });

    test(
      'a stopped take with a missed word keeps the miss and a try',
      () async {
        await startLive();
        session.debugApplyPartial(
          const SttPartial(
            transcript: 'el come',
            words: [],
            isFinal: true,
            speechFinal: false,
          ),
        );
        await recorder.stop();
        await pumpEventQueue();

        expect(recorder.phase, ReadAloudPhase.done);
        expect(recorder.heard, [true, false, true]);
        expect(recorder.triesLeft, 2);
      },
    );
  });

  group('ReadAloudRecorder on the batch route', () {
    test('records to a WAV, transcribes it and judges the words', () async {
      final capture = _FakeCapture();
      Uint8List? sent;
      final recorder = ReadAloudRecorder(
        reference: _reference,
        hasMicPermission: () async => true,
        streamingSessionFactory: null,
        captureFactory: () => capture,
        transcribe: (wav) async {
          sent = wav;
          return ['el', 'gato', 'come'];
        },
      );
      await recorder.start();
      expect(recorder.phase, ReadAloudPhase.recording);
      capture.pushFrame(Uint8List(320));
      await recorder.stop();

      expect(sent, isNotNull);
      expect(sent!.length, 44 + 320, reason: 'a WAV header over the PCM');
      expect(recorder.phase, ReadAloudPhase.done);
      expect(recorder.allHeard, isTrue);
      expect(recorder.lastTake!.duration, const Duration(milliseconds: 10));
      expect(capture.disposed, isTrue);
      recorder.dispose();
    });

    test('a refused relay falls back to the batch capture', () async {
      final repo = _FakeRepo();
      final capture = _FakeCapture();
      final recorder = ReadAloudRecorder(
        reference: _reference,
        hasMicPermission: () async => true,
        streamingSessionFactory: () => StreamingSttSession(
          capture: _FakeCapture(),
          repo: repo,
          tempFileWriter: _memWriter,
        ),
        captureFactory: () => capture,
        transcribe: (_) async => ['el'],
      );
      final starting = recorder.start();
      await pumpEventQueue();
      repo.emitState(SttStreamState.closed); // relay denied before ready
      await starting;

      expect(recorder.phase, ReadAloudPhase.recording);
      await recorder.stop();
      expect(recorder.heard, [true, false, false]);
      recorder.dispose();
    });

    test(
      'no route to transcribe fails the take without spending a try',
      () async {
        final recorder = ReadAloudRecorder(
          reference: _reference,
          hasMicPermission: () async => true,
          streamingSessionFactory: null,
          captureFactory: () => _FakeCapture(),
          transcribe: (_) async => null,
        );
        await recorder.start();
        await recorder.stop();

        expect(recorder.phase, ReadAloudPhase.failed);
        expect(recorder.triesUsed, 0);
        recorder.dispose();
      },
    );

    test('a refused microphone is reported, not recorded', () async {
      final recorder = ReadAloudRecorder(
        reference: _reference,
        hasMicPermission: () async => false,
        streamingSessionFactory: null,
        captureFactory: () => _FakeCapture(),
        transcribe: (_) async => const [],
      );
      await recorder.start();

      expect(recorder.phase, ReadAloudPhase.micUnavailable);
      expect(recorder.triesUsed, 0);
      recorder.dispose();
    });
  });
}
