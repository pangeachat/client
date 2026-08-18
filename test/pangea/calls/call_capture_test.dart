import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:livekit_client/livekit_client.dart';

import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';

class RecordingSink implements CallAudioSink {
  final List<PcmChunk> delivered = [];
  final List<int> failIndices;
  int closes = 0;
  Completer<void>? block;

  RecordingSink({this.failIndices = const []});

  @override
  Future<void> deliver(PcmChunk chunk) async {
    if (block != null) await block!.future;
    if (failIndices.contains(chunk.index)) {
      throw StateError('sink refused chunk ${chunk.index}');
    }
    delivered.add(chunk);
  }

  @override
  Future<void> close() async => closes++;
}

/// Stands in for a published track. [addAudioRenderer] is the only member the
/// recorder touches, and the real one is a plain callback registration.
class FakeTrack implements AudioTrack {
  AudioFrameCallback? onFrame;
  bool failNextRenderer = false;
  AudioRendererOptions? options;
  int cancels = 0;

  @override
  CancelListenFunc addAudioRenderer({
    required AudioFrameCallback onFrame,
    AudioRendererOptions options = const AudioRendererOptions(),
  }) {
    if (failNextRenderer) {
      failNextRenderer = false;
      throw StateError('no renderer available');
    }
    this.onFrame = onFrame;
    this.options = options;
    return () async {
      cancels++;
      this.onFrame = null;
    };
  }

  void emit(int ms, {double amplitude = 0.3}) {
    final count = captureSampleRate * ms ~/ 1000;
    final samples = Int16List(count);
    final peak = (amplitude * 32767).round();
    for (var i = 0; i < count; i++) {
      samples[i] = i.isEven ? peak : -peak;
    }
    onFrame?.call(
      AudioFrame(
        sampleRate: captureSampleRate,
        channels: captureChannels,
        data: samples.buffer.asUint8List(),
        format: AudioFormat.Int16,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late RecordingSink sink;
  late FakeTrack track;

  setUp(() {
    sink = RecordingSink();
    track = FakeTrack();
  });

  CallCaptureService service({RecordingSink? withSink}) => CallCaptureService(
    sink: withSink ?? sink,
    newChunker: (firstIndex) => PcmChunker(
      sampleRate: captureSampleRate,
      channels: captureChannels,
      targetDuration: const Duration(milliseconds: 200),
      maxDuration: const Duration(milliseconds: 400),
      minSilence: const Duration(milliseconds: 100),
      firstIndex: firstIndex,
    ),
  );

  group('CallCaptureService', () {
    test('requests the capture format rather than accepting the default', () {
      service().start(track);
      expect(track.options!.sampleRate, captureSampleRate);
      expect(track.options!.channels, captureChannels);
      expect(track.options!.format, AudioFormat.Int16);
    });

    test('delivers chunks as the call runs, not only at the end', () async {
      final s = service()..start(track);
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }
      await pumpEventQueue();
      expect(
        sink.delivered,
        isNotEmpty,
        reason: '600ms exceeds the 400ms ceiling',
      );
      await s.stop();
    });

    test('a tap that throws leaves nothing started', () {
      // Recording it as started would refuse every later attempt with "already
      // running", costing the call its analytics for a failure that may have
      // been momentary.
      final failing = FakeTrack()..failNextRenderer = true;
      final s = service();

      expect(() => s.start(failing), throwsStateError);
      expect(s.isRecording, isFalse);

      s.start(track);
      expect(s.isRecording, isTrue, reason: 'and a retry works');
    });

    test('numbering continues when recording resumes in the same call', () async {
      // Another of the learner's devices can take over recording and hand it
      // back within one call. A second stretch numbered from zero would look
      // like a redelivery of the first and be discarded as already transcribed.
      final s = service();
      s.start(track);
      for (var i = 0; i < 60; i++) {
        track.emit(20);
      }
      await s.stop();
      final firstRun = sink.delivered.map((c) => c.index).toList();
      expect(firstRun, isNotEmpty);

      s.start(track);
      for (var i = 0; i < 60; i++) {
        track.emit(20);
      }
      await s.stop();

      final all = sink.delivered.map((c) => c.index).toList();
      expect(
        all,
        List.generate(all.length, (i) => i),
        reason: 'one unbroken run of indices across both stretches',
      );
      expect(all.length, greaterThan(firstRun.length));
    });

    test('a second start while recording is refused', () {
      final s = service()..start(track);
      expect(() => s.start(track), throwsStateError);
    });

    test(
      'stop cancels the tap, flushes the tail, and closes the sink',
      () async {
        final s = service()..start(track);
        track.emit(100);
        await s.stop();

        expect(track.cancels, 1);
        expect(sink.delivered, hasLength(1), reason: 'the tail was flushed');
        expect(sink.closes, 1);
        expect(s.isRecording, isFalse);
      },
    );

    test('stopping twice does not double-flush or double-close', () async {
      final s = service()..start(track);
      track.emit(100);
      await s.stop();
      await s.stop();
      expect(sink.delivered, hasLength(1));
      expect(sink.closes, 1);
    });

    test('stop on a recorder that never started is a no-op', () async {
      await service().stop();
      expect(sink.closes, 0);
    });

    test('frames arriving after stop are ignored', () async {
      final s = service()..start(track);
      final captured = track.onFrame;
      await s.stop();
      final before = sink.delivered.length;

      // A renderer callback already in flight when the tap was cancelled.
      captured!(
        AudioFrame(
          sampleRate: captureSampleRate,
          channels: captureChannels,
          data: Int16List(captureSampleRate).buffer.asUint8List(),
          format: AudioFormat.Int16,
        ),
      );
      await pumpEventQueue();
      expect(sink.delivered, hasLength(before));
    });

    test('stop waits for chunks already handed to the sink', () async {
      final s = service()..start(track);
      sink.block = Completer<void>();
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }
      await pumpEventQueue();
      expect(sink.delivered, isEmpty, reason: 'delivery is held open');

      final stopped = s.stop();
      var done = false;
      unawaited(stopped.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse, reason: 'stop must not abandon spoken audio');

      sink.block!.complete();
      await stopped;
      expect(sink.delivered, isNotEmpty);
    });

    test(
      'a chunk the sink refuses does not fail the call or the hangup',
      () async {
        final failing = RecordingSink(failIndices: [0]);
        final s = service(withSink: failing)..start(track);
        for (var i = 0; i < 60; i++) {
          track.emit(20);
        }
        await pumpEventQueue();
        await s.stop();

        expect(failing.closes, 1, reason: 'the call still ended cleanly');
        expect(
          failing.delivered.map((c) => c.index),
          isNot(contains(0)),
          reason: 'the refused chunk is lost, and only that chunk',
        );
        expect(failing.delivered, isNotEmpty);
      },
    );
  });

  group('CallCaptureService.pcmOf', () {
    AudioFrame frameOf(Uint8List data, AudioFormat format) => AudioFrame(
      sampleRate: captureSampleRate,
      channels: 1,
      data: data,
      format: format,
    );

    test('reads int16 samples little-endian', () {
      final src = Int16List.fromList([0, 1, -1, 32767, -32768]);
      final out = CallCaptureService.pcmOf(
        frameOf(src.buffer.asUint8List(), AudioFormat.Int16),
      );
      expect(out, src);
    });

    test('reads a frame whose bytes sit at an odd offset', () {
      final src = Int16List.fromList([5, -6, 7]);
      final padded = Uint8List(src.lengthInBytes + 1)
        ..setRange(1, src.lengthInBytes + 1, src.buffer.asUint8List());
      final window = Uint8List.sublistView(padded, 1);
      expect(
        window.offsetInBytes.isOdd,
        isTrue,
        reason: 'this is the case a zero-copy view cannot handle',
      );
      expect(CallCaptureService.pcmOf(frameOf(window, AudioFormat.Int16)), src);
    });

    test('converts float32 samples and clamps out-of-range values', () {
      final src = Float32List.fromList([0.0, 1.0, -1.0, 0.5, 2.0, -2.0]);
      final out = CallCaptureService.pcmOf(
        frameOf(src.buffer.asUint8List(), AudioFormat.Float32),
      );
      expect(out, [0, 32767, -32767, 16384, 32767, -32767]);
    });
  });
}
