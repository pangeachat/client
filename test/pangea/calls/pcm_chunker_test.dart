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

/// When the run these chunkers stand for began. Any plausible Unix
/// millisecond: what the tests assert is that a chunk sits an exact number of
/// FRAMES after it, so the value itself only has to be nameable.
const runStart = 1700000000000;

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
    runStartedAtMs: runStart,
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
        runStartedAtMs: runStart,
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

  group('where a chunk sits', () {
    test('an oversized batch is positioned by frames, not by the loop', () {
      // One add() can cut several chunks in a single pass. Reading a clock at
      // each cut would stamp them all at whatever moment the loop reached them,
      // which is a fact about CPU time rather than about when anybody spoke.
      final c = chunker();
      final emitted = c.add(frame(10000)); // 10s against a 4s ceiling
      expect(emitted.length, greaterThanOrEqualTo(2));

      var framesBefore = 0;
      for (final chunk in emitted) {
        expect(chunk.startedAtMs, runStart + framesBefore * 1000 ~/ 24000);
        framesBefore += chunk.pcm.lengthInBytes ~/ 2;
      }
    });

    test('positions do not drift over a long call at an awkward rate', () {
      // 44.1 kHz in 7ms frames, so a chunk's length is not a whole number of
      // milliseconds and the truncation has somewhere to hide. Summing each
      // chunk's own duration loses a fraction per chunk and keeps it; a single
      // conversion from an exact frame count loses nothing.
      const rate = 44100;
      final c = PcmChunker(
        sampleRate: rate,
        channels: 1,
        runStartedAtMs: runStart,
        targetDuration: const Duration(seconds: 1),
        maxDuration: const Duration(seconds: 2),
        minSilence: const Duration(milliseconds: 200),
      );

      final emitted = <PcmChunk>[];
      for (var i = 0; i < 4000; i++) {
        final quiet = i % 160 >= 130;
        emitted.addAll(
          c.add(frame(7, amplitude: quiet ? 0 : 0.3, sampleRate: rate)),
        );
      }
      expect(emitted.length, greaterThan(10));

      var framesBefore = 0;
      var summed = runStart;
      for (final chunk in emitted) {
        expect(chunk.startedAtMs, runStart + framesBefore * 1000 ~/ rate);
        framesBefore += chunk.pcm.lengthInBytes ~/ 2;
        summed += chunk.duration.inMilliseconds;
      }

      expect(
        summed,
        isNot(runStart + framesBefore * 1000 ~/ rate),
        reason: 'and summing truncated durations really would have drifted',
      );
    });

    test('a run ends where its frames end, flushed or not', () {
      // The caller that starts the NEXT run reads this as the floor that run
      // cannot begin before, and it reads it either side of the flush. An
      // answer that counted only the frames already cut into chunks would
      // report the run ending before its last words.
      final c = chunker();
      c.add(frame(500));

      final beforeFlush = c.endedAtMs;
      expect(beforeFlush, runStart + 500);
      c.flush();
      expect(c.endedAtMs, beforeFlush);
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
  group('audio the capture path dropped before it arrived', () {
    test('cuts what was buffered, so no chunk spans the gap', () {
      // The gap has to become a BOUNDARY. Left inside a chunk, the samples
      // either side of it are contiguous bytes with 500ms of missing time
      // between them, and a word timing measured from the chunk's start lands
      // half a second early for everything after the seam -- with nothing in
      // the chunk that could say where the seam was.
      final c = chunker();
      c.add(frame(400));
      final cut = c.skip(500);

      expect(cut, isNotNull);
      expect(cut!.index, 0);
      expect(cut.duration.inMilliseconds, 400);
      expect(cut.startedAtMs, runStart);

      c.add(frame(300));
      final after = c.flush()!;
      expect(after.duration.inMilliseconds, 300);
    });

    test('places everything after it later by exactly the gap', () {
      // The corruption this exists to stop. A position is derived from a
      // running FRAME count, so frames that never arrived used to shift every
      // later chunk earlier than it was spoken -- cumulatively, for the rest of
      // the run, on a half that declares its positions pinned.
      final c = chunker();
      c.add(frame(400));
      c.skip(500);
      c.add(frame(300));

      expect(c.flush()!.startedAtMs, runStart + 400 + 500);
    });

    test('adds up over several gaps', () {
      // Cumulative is the whole shape of the bug: one drop moves everything
      // after it, and the next moves everything after that again.
      final c = chunker();
      c.add(frame(200));
      c.skip(100);
      c.add(frame(200));
      c.skip(300);
      c.add(frame(200));

      expect(c.flush()!.startedAtMs, runStart + 400 + 400);
    });

    test('moves the run end, so the next run cannot sit inside the gap', () {
      // `endedAtMs` is the floor the NEXT run may not begin before. A gap that
      // did not move it would let a later run be placed on top of audio this
      // one already accounts for.
      final c = chunker();
      c.add(frame(200));
      c.skip(700);

      expect(c.endedAtMs, runStart + 200 + 700);
    });

    test('needs nothing buffered to move the positions after it', () {
      // A drop can land immediately after a cut. There is nothing to cut a
      // second time, and the gap still happened.
      final c = chunker();
      final cut = c.skip(250);
      expect(cut, isNull);

      c.add(frame(100));
      expect(c.flush()!.startedAtMs, runStart + 250);
    });

    test('a gap of nothing is not a gap', () {
      // The ordinary frame carries a zero, a hundred times a second. It must
      // not cut a chunk, and it must not move anything.
      final c = chunker();
      c.add(frame(200));
      expect(c.skip(0), isNull);
      expect(c.skip(-5), isNull);
      c.add(frame(100));

      final only = c.flush()!;
      expect(only.index, 0);
      expect(only.startedAtMs, runStart);
      expect(only.duration.inMilliseconds, 300);
    });

    test('the cut it makes keeps the numbering', () {
      // A chunk cut by a gap is a chunk like any other: the sink keys a result
      // by index, so a gap that reused one would have the next chunk read as a
      // redelivery of it.
      final c = chunker();
      c.add(frame(100));
      final first = c.skip(100)!;
      c.add(frame(100));
      final second = c.flush()!;

      expect([first.index, second.index], [0, 1]);
      expect(c.nextIndex, 2);
    });
  });

  group('a device that captures at a higher rate', () {
    test('still produces chunks the route will accept', () {
      // The ninety-second ceiling was sized for the 16 kHz this app asks for.
      // Android hands over the audio module's own rate, routinely 48 kHz, which
      // is three times the bytes for the same ninety seconds — and the route
      // caps a request by size, not by duration.
      final c = PcmChunker(
        sampleRate: 48000,
        channels: 1,
        firstIndex: 0,
        runStartedAtMs: runStart,
      );
      final emitted = <PcmChunk>[];
      // Two minutes of unbroken speech at the higher rate.
      for (var i = 0; i < 240; i++) {
        emitted.addAll(c.add(frame(500, sampleRate: 48000)));
      }
      emitted.addAll([?c.flush()]);

      expect(emitted, isNotEmpty);
      for (final chunk in emitted) {
        expect(
          chunk.pcm.lengthInBytes,
          lessThanOrEqualTo(90 * 16000 * 2),
          reason: 'no chunk may exceed what the route accepts',
        );
      }
    });
  });
}
