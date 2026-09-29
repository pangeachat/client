import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_merge.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

/// A plausible SFU-clock instant the halves anchor to. What the tests assert is
/// that a half sits an exact number of samples after the earliest start, so the
/// value itself only has to be nameable.
const t0 = 1700000000000;

Int16List constantTone(int count, int value) {
  final samples = Int16List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = value;
  }
  return samples;
}

Uint8List monoWav(Int16List samples, int sampleRate) =>
    pcm16ToWav(_leBytes(samples), sampleRate: sampleRate, channels: 1);

Uint8List stereoWav(Int16List interleaved, int sampleRate) =>
    pcm16ToWav(_leBytes(interleaved), sampleRate: sampleRate, channels: 2);

Uint8List _leBytes(Int16List samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

/// Decodes a mono WAV emitted by [pcm16ToWav] back into its rate and samples.
({int sampleRate, Int16List samples}) decodeWav(Uint8List wav) {
  final view = ByteData.sublistView(wav);
  final sampleRate = view.getUint32(24, Endian.little);
  final dataLen = view.getUint32(40, Endian.little);
  final count = dataLen ~/ 2;
  final samples = Int16List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = view.getInt16(44 + i * 2, Endian.little);
  }
  return (sampleRate: sampleRate, samples: samples);
}

/// A valid PCM16 mono WAV with a metadata (`LIST`) chunk BEFORE `data`, so the
/// `data` chunk does not sit at the canonical byte-44 offset. Only a real
/// chunk-walking parser finds the samples; a parser that skips a fixed 44-byte
/// header reads the metadata filler as PCM instead.
Uint8List wavWithLeadingChunk(Int16List samples, int sampleRate) {
  final pcm = _leBytes(samples);
  // 'INFO' + four filler bytes: 8 bytes, already even (no pad needed).
  final listBody = Uint8List.fromList([
    0x49,
    0x4E,
    0x46,
    0x4F,
    0x11,
    0x22,
    0x33,
    0x44,
  ]);
  final riffPayload = 4 + (8 + 16) + (8 + listBody.length) + (8 + pcm.length);
  final out = Uint8List(8 + riffPayload);
  final view = ByteData.sublistView(out);
  var o = 0;
  void tag(String s) {
    for (final c in s.codeUnits) {
      out[o++] = c;
    }
  }

  void u32(int v) {
    view.setUint32(o, v, Endian.little);
    o += 4;
  }

  void u16(int v) {
    view.setUint16(o, v, Endian.little);
    o += 2;
  }

  tag('RIFF');
  u32(riffPayload);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits
  tag('LIST');
  u32(listBody.length);
  out.setRange(o, o + listBody.length, listBody);
  o += listBody.length;
  tag('data');
  u32(pcm.length);
  out.setRange(o, o + pcm.length, pcm);
  return out;
}

/// A valid PCM16 mono WAV whose leading metadata chunk has an ODD body length,
/// so the following `data` chunk only lands on an even boundary if the parser
/// applies RIFF word-alignment padding. Without the pad the walk lands one byte
/// short of `data` and never finds it.
Uint8List wavWithOddChunk(Int16List samples, int sampleRate) {
  final pcm = _leBytes(samples);
  // 'INFO' + one byte: 5 bytes (odd) -> needs one pad byte to word-align.
  final listBody = Uint8List.fromList([0x49, 0x4E, 0x46, 0x4F, 0x55]);
  const listPadded = 6; // 5 + 1 pad
  final riffPayload = 4 + (8 + 16) + (8 + listPadded) + (8 + pcm.length);
  final out = Uint8List(8 + riffPayload);
  final view = ByteData.sublistView(out);
  var o = 0;
  void tag(String s) {
    for (final c in s.codeUnits) {
      out[o++] = c;
    }
  }

  void u32(int v) {
    view.setUint32(o, v, Endian.little);
    o += 4;
  }

  void u16(int v) {
    view.setUint16(o, v, Endian.little);
    o += 2;
  }

  tag('RIFF');
  u32(riffPayload);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  tag('LIST');
  u32(listBody.length); // declares 5, the odd true size
  out.setRange(o, o + listBody.length, listBody);
  o += listBody.length;
  out[o++] = 0; // the word-alignment pad byte
  tag('data');
  u32(pcm.length);
  out.setRange(o, o + pcm.length, pcm);
  return out;
}

/// A WAV with a fully specified `fmt ` chunk, for building non-PCM16-mono blobs
/// (float format, other bit depths) that the mixer must skip.
Uint8List customWav({
  required int audioFormat,
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required Uint8List body,
}) {
  final out = Uint8List(44 + body.length);
  final view = ByteData.sublistView(out);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  var o = 0;
  void tag(String s) {
    for (final c in s.codeUnits) {
      out[o++] = c;
    }
  }

  void u32(int v) {
    view.setUint32(o, v, Endian.little);
    o += 4;
  }

  void u16(int v) {
    view.setUint16(o, v, Endian.little);
    o += 2;
  }

  tag('RIFF');
  u32(36 + body.length);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(audioFormat);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * blockAlign);
  u16(blockAlign);
  u16(bitsPerSample);
  tag('data');
  u32(body.length);
  out.setRange(44, 44 + body.length, body);
  return out;
}

CallAudioMergeSource src(Uint8List wav, int? startMs, String sender) =>
    CallAudioMergeSource(wav: wav, fileStartSfuMs: startMs, senderId: sender);

CallAudioMergeResult merge(
  List<CallAudioMergeSource> sources, {
  int expectedUsers = 2,
  int maxDurationMs = 600000,
}) => mergeCallAudio(
  CallAudioMergeRequest(
    sources: sources,
    expectedUsers: expectedUsers,
    maxDurationMs: maxDurationMs,
  ),
);

void main() {
  group('mergeCallAudio', () {
    test('delays the later half by its start offset', () {
      // Two 48k one-second halves; B starts 500 ms after A -> 24000 samples.
      final a = monoWav(constantTone(48000, 1000), 48000);
      final b = monoWav(constantTone(48000, 2000), 48000);

      final result = merge([src(a, t0, '@a'), src(b, t0 + 500, '@b')]);
      final out = decodeWav(result.wav);

      expect(out.sampleRate, 48000);
      // A ends at 48000, B ends at 24000 + 48000 -> the later, 72000.
      expect(out.samples.length, 72000);
      // A-only lead-in: (1000 + 0) / 2.
      expect(out.samples[0], 500);
      expect(out.samples[23999], 500);
      // Overlap once B lands at exactly sample 24000: (1000 + 2000) / 2.
      expect(out.samples[24000], 1500);
      expect(out.samples[47999], 1500);
      // B-only tail after A ends: (0 + 2000) / 2.
      expect(out.samples[48000], 1000);
      expect(out.samples[71999], 1000);
      expect(result.complete, isTrue);
    });

    group('averages over the expected user count', () {
      test('overlapping speakers average, they do not sum', () {
        final a = monoWav(constantTone(24000, 1000), 48000);
        final b = monoWav(constantTone(24000, 2000), 48000);

        final out = decodeWav(merge([src(a, t0, '@a'), src(b, t0, '@b')]).wav);

        // (1000 + 2000) / 2 == 1500, never the raw sum 3000.
        expect(out.samples[12000], 1500);
      });

      test('a single speaker still divides by U, not by active count', () {
        // A runs the whole time; B joins 250 ms late (sample 12000), so the
        // early stretch has exactly one half present. Constant 1/U makes that
        // stretch (1000 + 0) / 2 == 500 -- dividing by the active count (1)
        // would give 1000, and summing would also give 1000.
        final a = monoWav(constantTone(24000, 1000), 48000);
        final b = monoWav(constantTone(24000, 2000), 48000);

        final out = decodeWav(
          merge([src(a, t0, '@a'), src(b, t0 + 250, '@b')]).wav,
        );

        expect(out.samples[6000], 500);
      });

      test('rounds the average, it does not truncate', () {
        // Odd sum: (1001 + 2000) / 2 == 1500.5, which rounds to 1501.
        // Truncating (floor) would give 1500.
        final a = monoWav(constantTone(24000, 1001), 48000);
        final b = monoWav(constantTone(24000, 2000), 48000);

        final out = decodeWav(merge([src(a, t0, '@a'), src(b, t0, '@b')]).wav);

        expect(out.samples[12000], 1501);
      });

      test('keeps averaging headroom -- no clip before the divide', () {
        // Loud overlap: (32000 + 30000) / 2 == 31000. Clipping the running sum
        // to the Int16 max before dividing would collapse this to ~16383.
        final a = monoWav(constantTone(24000, 32000), 48000);
        final b = monoWav(constantTone(24000, 30000), 48000);

        final out = decodeWav(merge([src(a, t0, '@a'), src(b, t0, '@b')]).wav);

        expect(out.samples[12000], 31000);
      });
    });

    group('resamples a divergent half to the common rate', () {
      test('a 16k half meets a 48k half at 48000 across the full span', () {
        final a48 = monoWav(constantTone(48000, 6000), 48000);
        final b16 = monoWav(constantTone(16000, 3000), 16000);

        final result = merge([src(a48, t0, '@a'), src(b16, t0, '@b')]);
        final out = decodeWav(result.wav);

        expect(out.sampleRate, 48000);
        // 16000 upsampled 3x == 48000: same span as the 48k half.
        expect(out.samples.length, 48000);
        expect(result.durationMs, 1000);
        // Mid-span the resampled B is present everywhere: (6000 + 3000) / 2.
        // Not resampled, B would cover only [0, 16000) and this would be 3000.
        expect(out.samples[24000], 4500);
        expect(out.samples[40000], 4500);
      });

      test('interpolates a ramp: exact at multiples, rising in between', () {
        // A silent 48k partner isolates the resampled 16k contribution:
        // out[m] == round(upsampledRamp[m] / 2).
        final ramp = Int16List(100);
        for (var i = 0; i < ramp.length; i++) {
          ramp[i] = i * 300; // 0..29700, even -> an exact halving.
        }
        final b16 = monoWav(ramp, 16000);
        final a48 = monoWav(constantTone(300, 0), 48000);

        final out = decodeWav(
          merge([src(a48, t0, '@a'), src(b16, t0, '@b')]).wav,
        );

        expect(out.sampleRate, 48000);
        expect(out.samples.length, 300); // 100 upsampled 3x.
        // Phase 0 is an exact delta: each original 16k sample lands unchanged at
        // output index 3*i. Proves the upsampled samples land at the right spots.
        for (var i = 0; i < ramp.length; i++) {
          expect(
            out.samples[3 * i],
            (ramp[i] / 2).round(),
            reason: 'ramp sample $i should land at output index ${3 * i}',
          );
        }
        // A genuine interpolator fills the between-sample outputs, so an interior
        // stretch of the upsampled ramp rises at EVERY output step. A
        // nearest-neighbor / sample-and-hold resampler would repeat each value
        // three times -- a staircase that is not strictly increasing.
        for (var m = 30; m < 270; m++) {
          expect(
            out.samples[m + 1] > out.samples[m],
            isTrue,
            reason: 'upsampled ramp must strictly increase at output index $m',
          );
        }
      });
    });

    test('walks RIFF chunks to find data after a leading metadata chunk', () {
      // The half carries a LIST chunk before data, so data is not at byte 44.
      // A chunk-walking parser reads the real tone; a fixed-44-byte parser would
      // read the LIST filler as PCM (wrong values and wrong length).
      final withMeta = wavWithLeadingChunk(constantTone(48000, 4000), 48000);
      final silent = monoWav(constantTone(48000, 0), 48000);

      final result = merge([src(withMeta, t0, '@a'), src(silent, t0, '@b')]);
      final out = decodeWav(result.wav);

      expect(
        out.samples.length,
        48000,
      ); // the real data length, not filler+data.
      // EVERY sample is the real tone averaged with silence (== 2000). A fixed
      // 44-byte parser would read the LIST filler as the FIRST samples (a
      // different, non-2000 value) and a different length, so asserting the WHOLE
      // output -- the early samples in the filler region especially -- fails it.
      // (Checking only a late sample, past the small filler prefix, would not:
      // that offset lands in real data even for a fixed-44 parser.)
      expect(out.samples.every((s) => s == 2000), isTrue);
      expect(result.complete, isTrue); // parsed cleanly as a kept half.
    });

    test('applies word-alignment padding after an odd-length chunk', () {
      // The leading metadata chunk has an odd body, so data only aligns if the
      // parser pads odd chunks to an even boundary. Without the pad it lands one
      // byte short of data, fails to find it, and skips the whole half.
      final withOdd = wavWithOddChunk(constantTone(48000, 5000), 48000);
      final silent = monoWav(constantTone(48000, 0), 48000);

      final result = merge([src(withOdd, t0, '@a'), src(silent, t0, '@b')]);
      final out = decodeWav(result.wav);

      expect(result.complete, isTrue); // the padded half is found and kept.
      expect(out.samples.length, 48000);
      expect(out.samples[100], 2500); // (5000 + 0) / 2 -- the real samples.
    });

    group('skips unplaceable halves and reports completeness', () {
      test('a clean two-half merge is complete with sorted coverage', () {
        final a = monoWav(constantTone(48000, 1000), 48000);
        final b = monoWav(constantTone(48000, 2000), 48000);

        final result = merge([src(b, t0, '@b'), src(a, t0, '@a')]);

        expect(result.complete, isTrue);
        expect(result.sourceCoverage, ['@a', '@b']);
      });

      test('a null-anchor half is skipped and the merge is incomplete', () {
        final a = monoWav(constantTone(48000, 1000), 48000);
        final b = monoWav(constantTone(48000, 2000), 48000);

        final result = merge([src(a, t0, '@a'), src(b, null, '@b')]);
        final out = decodeWav(result.wav);

        expect(result.complete, isFalse);
        expect(result.sourceCoverage, ['@a']); // B is excluded from coverage.
        // A is still placed and averaged over U: (1000 + 0) / 2.
        expect(out.samples[0], 500);
      });

      test('a stereo half is skipped and the merge is incomplete', () {
        final a = monoWav(constantTone(48000, 1000), 48000);
        // 48000 stereo frames = 96000 interleaved samples -> channels != 1.
        final stereo = stereoWav(constantTone(96000, 2000), 48000);

        final result = merge([src(a, t0, '@a'), src(stereo, t0, '@b')]);

        expect(result.complete, isFalse);
        expect(result.sourceCoverage, ['@a']);
      });

      test('a non-PCM (float) format half is skipped', () {
        final a = monoWav(constantTone(48000, 1000), 48000);
        // audioFormat 3 == IEEE float: not PCM, must be skipped.
        final float = customWav(
          audioFormat: 3,
          channels: 1,
          sampleRate: 48000,
          bitsPerSample: 32,
          body: Uint8List(4000),
        );

        final result = merge([src(a, t0, '@a'), src(float, t0, '@b')]);

        expect(result.complete, isFalse);
        expect(result.sourceCoverage, ['@a']);
      });

      test('a non-16-bit depth half is skipped', () {
        final a = monoWav(constantTone(48000, 1000), 48000);
        // 8-bit PCM: right format tag, wrong depth -> must be skipped.
        final eightBit = customWav(
          audioFormat: 1,
          channels: 1,
          sampleRate: 48000,
          bitsPerSample: 8,
          body: Uint8List(4000),
        );

        final result = merge([src(a, t0, '@a'), src(eightBit, t0, '@b')]);

        expect(result.complete, isFalse);
        expect(result.sourceCoverage, ['@a']);
      });
    });

    test('caps the output at the duration ceiling and marks it incomplete', () {
      // Two aligned 2s halves, but a 1s ceiling.
      final a = monoWav(constantTone(96000, 1000), 48000);
      final b = monoWav(constantTone(96000, 2000), 48000);

      final result = merge([
        src(a, t0, '@a'),
        src(b, t0, '@b'),
      ], maxDurationMs: 1000);
      final out = decodeWav(result.wav);

      // 1000 ms * 48000 == 48000 samples, not the uncapped 96000.
      expect(out.samples.length, 48000);
      expect(result.durationMs, 1000);
      expect(result.complete, isFalse);
      // Content up to the cap is still the real average: (1000 + 2000) / 2.
      expect(out.samples[100], 1500);
    });

    test('a non-positive ceiling yields an empty incomplete merge, not a '
        'negative allocation', () {
      // A zero/negative ceiling must not compute a negative sample count and
      // crash on Int16List(negative); it produces an empty, incomplete result.
      final a = monoWav(constantTone(48000, 1000), 48000);
      final b = monoWav(constantTone(48000, 2000), 48000);

      for (final cap in [0, -1000]) {
        final result = merge([
          src(a, t0, '@a'),
          src(b, t0, '@b'),
        ], maxDurationMs: cap);
        expect(result.durationMs, 0, reason: 'cap=$cap');
        expect(result.complete, isFalse, reason: 'cap=$cap');
        expect(decodeWav(result.wav).samples, isEmpty, reason: 'cap=$cap');
        // These pin the EARLY-RETURN path specifically (distinguishing it from
        // the normal cap path, which for cap==0 would also yield empty/incomplete
        // but at the parsed common rate with non-empty coverage): the early
        // return stamps the 16000 fallback rate and empty coverage. This kills a
        // `<= 0` -> `< 0` mutation, which would let cap==0 fall through.
        expect(result.sampleRate, 16000, reason: 'cap=$cap');
        expect(result.sourceCoverage, isEmpty, reason: 'cap=$cap');
      }
    });

    test('a call whose timeline lands exactly on the ceiling is complete', () {
      // Two aligned 1s halves == 48000 samples, a 1s ceiling == 48000 samples:
      // outLenUncapped == maxSamples EXACTLY. `truncated` is `>` (not `>=`), so
      // this is a full, complete merge. A `>=` mutation would wrongly mark it
      // incomplete -> this pins that boundary.
      final a = monoWav(constantTone(48000, 1000), 48000);
      final b = monoWav(constantTone(48000, 2000), 48000);

      final result = merge([
        src(a, t0, '@a'),
        src(b, t0, '@b'),
      ], maxDurationMs: 1000);

      expect(decodeWav(result.wav).samples.length, 48000);
      expect(result.complete, isTrue);
    });

    test('the output cap trims a late half whose delay pushes it past the '
        'ceiling, independent of input clamping', () {
      // Both halves are 1s (48000 samples) -- WELL WITHIN a 2s (96000-sample)
      // ceiling, so NEITHER input is clamped at parse. B starts 1.5s late
      // (delay 72000), so the aligned timeline runs to 72000 + 48000 = 120000,
      // past the 96000 cap. Only the OUTPUT cap can trim that; the input clamp
      // cannot, since the inputs fit. Removing the output cap would leave the
      // length at 120000 -- this isolates and pins the output-cap path.
      final a = monoWav(constantTone(48000, 1000), 48000);
      final b = monoWav(constantTone(48000, 2000), 48000);

      final result = merge([
        src(a, t0, '@a'),
        src(b, t0 + 1500, '@b'),
      ], maxDurationMs: 2000);
      final out = decodeWav(result.wav);

      expect(out.samples.length, 96000); // capped, not the uncapped 120000.
      expect(result.durationMs, 2000);
      expect(result.complete, isFalse);
      // Content inside the cap is the real merge: A-only lead-in is 1000/2, and
      // B's region (from 72000) before the cut is 2000/2.
      expect(out.samples[0], 500);
      expect(out.samples[90000], 1000);
    });
  });
}
