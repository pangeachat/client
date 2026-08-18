import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';

/// A frame of [ms] milliseconds at [amplitude], where 0 is digital silence and
/// 1.0 is full scale.
Int16List frame(int ms, {double amplitude = 0.3, int sampleRate = 24000}) {
  final count = sampleRate * ms ~/ 1000;
  final out = Int16List(count);
  final peak = (amplitude * 32767).round();
  // Alternating sign so the RMS matches the amplitude rather than averaging to
  // zero, which is what a DC-filled buffer would do.
  for (var i = 0; i < count; i++) {
    out[i] = i.isEven ? peak : -peak;
  }
  return out;
}

int totalSamples(List<PcmChunk> chunks) =>
    chunks.fold(0, (sum, c) => sum + c.pcm.lengthInBytes ~/ 2);

void main() {
  PcmChunker chunker({
    Duration target = const Duration(seconds: 2),
    Duration max = const Duration(seconds: 4),
    Duration minSilence = const Duration(milliseconds: 300),
  }) => PcmChunker(
    sampleRate: 24000,
    channels: 1,
    targetDuration: target,
    maxDuration: max,
    minSilence: minSilence,
  );

  group('PcmChunker', () {
    test('emits nothing before the target duration', () {
      final c = chunker();
      var emitted = <PcmChunk>[];
      for (var i = 0; i < 50; i++) {
        emitted += c.add(frame(20));
      }
      expect(emitted, isEmpty, reason: '1s of audio is under the 2s target');
    });

    test('cuts at silence once past the target', () {
      final c = chunker();
      final emitted = <PcmChunk>[];
      // 2.5s of speech: past the target, but no silence yet, so no cut.
      for (var i = 0; i < 125; i++) {
        emitted.addAll(c.add(frame(20)));
      }
      expect(emitted, isEmpty, reason: 'past target but still speaking');

      // 300ms of silence completes the boundary.
      for (var i = 0; i < 15; i++) {
        emitted.addAll(c.add(frame(20, amplitude: 0)));
      }
      expect(emitted, hasLength(1));
      expect(emitted.single.index, 0);
    });

    test('cuts at the hard maximum even with no silence at all', () {
      final c = chunker();
      final emitted = <PcmChunk>[];
      for (var i = 0; i < 250; i++) {
        emitted.addAll(c.add(frame(20)));
      }
      // 5s of unbroken speech must have been cut by the 4s ceiling.
      expect(emitted, hasLength(1));
      expect(
        emitted.single.duration.inMilliseconds,
        greaterThanOrEqualTo(4000),
      );
      expect(
        emitted.single.duration.inMilliseconds,
        lessThan(4100),
        reason: 'cuts are frame-aligned, so overshoot is bounded by one frame',
      );
    });

    test('brief pauses do not cut', () {
      final c = chunker();
      final emitted = <PcmChunk>[];
      for (var i = 0; i < 125; i++) {
        emitted.addAll(c.add(frame(20)));
      }
      // 100ms of silence is under minSilence — a breath, not a boundary.
      for (var i = 0; i < 5; i++) {
        emitted.addAll(c.add(frame(20, amplitude: 0)));
      }
      expect(emitted, isEmpty);
    });

    test('the silence run resets when speech resumes', () {
      final c = chunker();
      final emitted = <PcmChunk>[];
      for (var i = 0; i < 125; i++) {
        emitted.addAll(c.add(frame(20)));
      }
      for (var i = 0; i < 10; i++) {
        emitted.addAll(c.add(frame(20, amplitude: 0))); // 200ms
      }
      emitted.addAll(c.add(frame(20))); // speech
      for (var i = 0; i < 10; i++) {
        emitted.addAll(c.add(frame(20, amplitude: 0))); // 200ms again
      }
      expect(emitted, isEmpty, reason: 'two 200ms gaps are not one 400ms gap');
    });

    test('flush emits the tail and flushing twice emits nothing', () {
      final c = chunker();
      c.add(frame(500));
      final tail = c.flush();
      expect(tail, isNotNull);
      expect(tail!.pcm.lengthInBytes, 24000 * 2 ~/ 2);
      expect(c.flush(), isNull, reason: 'nothing is left to flush');
    });

    test('flush on an empty chunker emits nothing', () {
      expect(chunker().flush(), isNull);
    });

    test('chunk indices are contiguous from zero', () {
      final c = chunker();
      final emitted = <PcmChunk>[];
      for (var i = 0; i < 1000; i++) {
        emitted.addAll(c.add(frame(20)));
      }
      final tail = c.flush();
      if (tail != null) emitted.add(tail);
      expect(emitted.length, greaterThan(3));
      expect(
        emitted.map((c) => c.index).toList(),
        List.generate(emitted.length, (i) => i),
      );
    });

    test('one oversized frame is split rather than exceeding the ceiling', () {
      // A renderer that batches its callbacks can hand over more audio in one
      // call than the ceiling allows. Appending it whole would produce a chunk
      // the upload cap rejects, and the earlier tests could not see it because
      // they all feed 5-60ms frames.
      final c = chunker();
      final emitted = c.add(frame(10000)); // 10s against a 4s ceiling

      expect(emitted.length, greaterThanOrEqualTo(2));
      for (final chunk in emitted) {
        expect(
          chunk.duration.inMilliseconds,
          lessThanOrEqualTo(4000),
          reason: 'no chunk may exceed the ceiling the upload cap sets',
        );
      }
      final tail = c.flush();
      final all = [...emitted, ?tail];
      expect(totalSamples(all), 24000 * 10, reason: 'and nothing is lost');
      expect(
        all.map((chunk) => chunk.index).toList(),
        List.generate(all.length, (i) => i),
      );
    });

    /// The invariant the whole analytics contract rests on: a speaker's credit is
    /// the union of their chunks, so the chunks must be the input exactly once,
    /// in order. A dropped or duplicated sample is a silently wrong transcript.
    test('every input sample lands in exactly one chunk, in order', () {
      final c = chunker();
      final input = <int>[];
      final emitted = <PcmChunk>[];

      // Varied frame sizes and amplitudes, so cuts land at silence, at the
      // ceiling, and mid-buffer over the same run.
      final sizes = [10, 20, 5, 40, 20, 20, 60, 20];
      for (var i = 0; i < 400; i++) {
        final quiet = i % 37 < 4;
        final f = frame(sizes[i % sizes.length], amplitude: quiet ? 0 : 0.3);
        input.addAll(f);
        emitted.addAll(c.add(f));
      }
      final tail = c.flush();
      if (tail != null) emitted.add(tail);

      expect(totalSamples(emitted), input.length, reason: 'no sample lost');

      final rejoined = <int>[];
      for (final chunk in emitted) {
        rejoined.addAll(
          chunk.pcm.buffer.asInt16List(
            chunk.pcm.offsetInBytes,
            chunk.pcm.lengthInBytes ~/ 2,
          ),
        );
      }
      expect(rejoined, input, reason: 'concatenating the chunks is the input');
    });

    test('a chunk carries the format its samples were captured at', () {
      final c = PcmChunker(
        sampleRate: 16000,
        channels: 2,
        targetDuration: const Duration(milliseconds: 100),
        maxDuration: const Duration(milliseconds: 200),
        minSilence: const Duration(milliseconds: 50),
      );
      c.add(frame(300, sampleRate: 16000));
      final chunk = c.flush()!;
      expect(chunk.sampleRate, 16000);
      expect(chunk.channels, 2);
    });
  });

  group('PcmChunk.toWav', () {
    test('writes a header the length of the payload agrees with', () {
      final c = chunker();
      c.add(frame(1000));
      final wav = c.flush()!.toWav();
      final bytes = ByteData.sublistView(wav);

      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      expect(bytes.getUint32(4, Endian.little), wav.length - 8);
      expect(bytes.getUint32(40, Endian.little), wav.length - 44);
      expect(bytes.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(bytes.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(bytes.getUint32(24, Endian.little), 24000);
      expect(bytes.getUint16(34, Endian.little), 16, reason: '16-bit');
      // byte rate = rate * channels * bytesPerSample
      expect(bytes.getUint32(28, Endian.little), 24000 * 1 * 2);
      expect(bytes.getUint16(32, Endian.little), 2, reason: 'block align');
    });

    test('preserves the samples verbatim', () {
      final c = chunker();
      final f = frame(100);
      c.add(f);
      final wav = c.flush()!.toWav();
      final payload = wav.buffer.asInt16List(44 + wav.offsetInBytes, f.length);
      expect(payload, f);
    });
  });
}
