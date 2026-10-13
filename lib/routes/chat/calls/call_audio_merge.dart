import 'dart:math';
import 'dart:typed_data';

import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

/// One per-device recording half handed to [mergeCallAudio].
///
/// v1 mixes exactly two of these (one per user in a 1:1 call). Each is a mono
/// PCM16 WAV at the device's delivered rate, anchored to the shared SFU clock.
class CallAudioMergeSource {
  /// The half's WAV bytes (RIFF/WAVE, PCM16 mono at the device's delivered
  /// rate). Parsed by walking chunks; a non-PCM16-mono blob is skipped.
  final Uint8List wav;

  /// Absolute SFU-clock start of this half (`clockAnchor.sfuMs + offset`) — the
  /// shared-timeline anchor read straight off the per-device event. Null when
  /// the half lacks an anchor/offset, in which case it cannot be placed on the
  /// timeline and is skipped.
  final int? fileStartSfuMs;

  /// The Matrix sender of the half. Used only as this merge's coverage
  /// identity; never as an input to the mix math.
  final String senderId;

  /// Where this source stops counting, on the SFU's clock: the moment the
  /// device the learner moved the call to began recording (client#9173). Null
  /// for a source that ends its speaker's side of the call. What comes after
  /// it is the moved-from device's hold -- silence while its successor speaks
  /// -- and is cut rather than mixed over the successor.
  final int? trimEndSfuMs;

  const CallAudioMergeSource({
    required this.wav,
    required this.fileStartSfuMs,
    required this.senderId,
    this.trimEndSfuMs,
  });
}

/// The single argument to [mergeCallAudio], so the function is one-argument and
/// therefore `compute()`-runnable (all fields cross an isolate boundary as
/// plain sendable values).
class CallAudioMergeRequest {
  /// The halves to mix (v1: exactly two, one per user).
  final List<CallAudioMergeSource> sources;

  /// The sealed expected participant count (v1: constant 2). Every output
  /// sample is divided by this, so a missing or silent half still divides by U
  /// — reproducing the validated `amix normalize=1` (constant 1/U per user).
  final int expectedUsers;

  /// The recording ceiling in milliseconds. The merged output never exceeds it;
  /// a merge that would run past the ceiling is truncated and marked
  /// incomplete.
  final int maxDurationMs;

  const CallAudioMergeRequest({
    required this.sources,
    required this.expectedUsers,
    required this.maxDurationMs,
  });
}

/// The result of [mergeCallAudio]: the merged mono WAV plus the small metadata
/// the caller needs to post it. Plain sendable fields, so it returns cleanly
/// from `compute()`.
class CallAudioMergeResult {
  /// The merged mono PCM16 WAV bytes (emitted through [pcm16ToWav]).
  final Uint8List wav;

  /// Duration of the merged output in milliseconds.
  final int durationMs;

  /// The common sample rate of the output (the max rate among mixed halves).
  final int sampleRate;

  /// Channel count of the output (always 1 — mono).
  final int channels;

  /// Sorted sender ids of the halves actually mixed — this merge's coverage.
  /// Skipped halves are absent. The writer maps these to the per-device event
  /// ids for the posted event's `source_event_ids`.
  final List<String> sourceCoverage;

  /// True only when every provided half was kept, the mixed count matched
  /// [CallAudioMergeRequest.expectedUsers], and the ceiling did not truncate the
  /// output. Any skip, a missing half, or a ceiling cut makes this false.
  final bool complete;

  const CallAudioMergeResult({
    required this.wav,
    required this.durationMs,
    required this.sampleRate,
    required this.channels,
    required this.sourceCoverage,
    required this.complete,
  });
}

/// Merges the per-device call-audio halves into one mono WAV of the whole call.
///
/// Pure and deterministic: the same request always yields the same bytes. It is
/// a top-level one-argument function so it runs under `compute()` on native, and
/// it is called directly (synchronously) by the tests.
///
/// The pipeline, per the design:
/// 1. Parse each WAV (walk RIFF chunks; read samples little-endian). Skip any
///    half that is not PCM16 mono or has a null [CallAudioMergeSource.fileStartSfuMs]
///    and mark the result incomplete.
/// 2. Common rate = the max rate among kept halves. Resample only a divergent
///    lower-rate half up to it (exact integer factor, e.g. 16k -> 48k = 3x) with
///    a windowed-sinc polyphase kernel.
/// 3. Align on `t0 = min(fileStartSfuMs)`; delay each half
///    `round((fileStartSfuMs - t0) / 1000 * rate)` samples; average over
///    `expectedUsers` (constant U), out-of-range samples counting as 0.
/// 4. Emit through [pcm16ToWav].
///
/// The output length is known up front, so the Int16 buffer is preallocated once
/// and filled window by window (no growing builder). The output is capped at
/// [CallAudioMergeRequest.maxDurationMs]; a merge that would exceed the ceiling
/// stops at it and is marked incomplete.
CallAudioMergeResult mergeCallAudio(CallAudioMergeRequest request) {
  // A WAV rate to stamp on a degenerate (empty) output when there is no kept
  // half to take a common rate from; matches the app's mic-request default.
  const fallbackRate = 16000;

  final expectedUsers = request.expectedUsers;
  // Guard the divisor without changing v1 behaviour (U is always >= 2 here);
  // this only stops a malformed U <= 0 from dividing by zero.
  final divisor = expectedUsers < 1 ? 1 : expectedUsers;
  final maxDurationMs = request.maxDurationMs;

  // A non-positive ceiling cannot bound any output; return an empty, incomplete
  // result rather than computing a negative allocation length downstream.
  if (maxDurationMs <= 0) {
    return _emptyResult(fallbackRate);
  }

  // Pass 1: parse and keep only placeable PCM16 mono halves with a valid anchor.
  var anySkipped = false;
  final kept = <_KeptHalf>[];
  for (final source in request.sources) {
    final start = source.fileStartSfuMs;
    final parsed = _parsePcm16MonoWav(source.wav);
    if (start == null || parsed == null) {
      anySkipped = true;
      continue;
    }
    var samples = parsed.samples;
    final trimEnd = source.trimEndSfuMs;
    if (trimEnd != null) {
      final keep = ((trimEnd - start) / 1000 * parsed.sampleRate).round();
      if (keep < samples.length) {
        samples = Int16List.sublistView(samples, 0, keep < 0 ? 0 : keep);
      }
    }
    kept.add(
      _KeptHalf(
        sampleRate: parsed.sampleRate,
        samples: samples,
        fileStartSfuMs: start,
        senderId: source.senderId,
      ),
    );
  }

  if (kept.isEmpty) {
    return _emptyResult(fallbackRate);
  }

  // Common rate = the max present. A 48k half meeting a 16k half yields 48k.
  var commonRate = kept.first.sampleRate;
  for (final half in kept) {
    if (half.sampleRate > commonRate) {
      commonRate = half.sampleRate;
    }
  }

  // Pass 2: align on the earliest start, resampling only divergent halves up.
  final t0 = kept.map((half) => half.fileStartSfuMs).reduce(min);
  final tracks = <_Track>[];
  for (final half in kept) {
    final Int16List samples;
    if (half.sampleRate == commonRate) {
      samples = half.samples;
    } else if (commonRate % half.sampleRate == 0) {
      samples = _upsampleInteger(half.samples, commonRate ~/ half.sampleRate);
    } else {
      // A non-integer rate ratio is outside v1's 16k/48k shape. Refuse to
      // mis-place it rather than resample it wrongly.
      anySkipped = true;
      continue;
    }
    final delay = ((half.fileStartSfuMs - t0) / 1000 * commonRate).round();
    tracks.add(_Track(samples: samples, delay: delay, senderId: half.senderId));
  }

  if (tracks.isEmpty) {
    return _emptyResult(commonRate);
  }

  // Output length is max(delay + length), capped at the ceiling.
  var outLenUncapped = 0;
  for (final track in tracks) {
    final end = track.delay + track.samples.length;
    if (end > outLenUncapped) {
      outLenUncapped = end;
    }
  }
  final maxSamples = (maxDurationMs * commonRate) ~/ 1000;
  final outLen = outLenUncapped < maxSamples ? outLenUncapped : maxSamples;
  // Truncated (and therefore incomplete) when the aligned timeline overran the
  // ceiling — the only cap: a too-long call, or a late half whose delay pushes
  // it past the ceiling, is cut here.
  final truncated = outLenUncapped > maxSamples;

  // Preallocate the Int16 output once and fill it window by window. Averaging
  // two Int16 samples over U cannot overflow Int16, so there is no clip here.
  final out = Int16List(outLen);
  final windowSamples = commonRate; // ~1s of samples: a bounded work unit.
  for (
    var windowStart = 0;
    windowStart < outLen;
    windowStart += windowSamples
  ) {
    final windowEnd = min(windowStart + windowSamples, outLen);
    for (var i = windowStart; i < windowEnd; i++) {
      var sum = 0;
      for (final track in tracks) {
        final si = i - track.delay;
        if (si >= 0 && si < track.samples.length) {
          sum += track.samples[si];
        }
      }
      out[i] = (sum / divisor).round();
    }
  }

  // Serialize the samples little-endian and emit through the shared WAV writer.
  final pcmBytes = Uint8List(outLen * 2);
  final pcmView = ByteData.sublistView(pcmBytes);
  for (var i = 0; i < outLen; i++) {
    pcmView.setInt16(i * 2, out[i], Endian.little);
  }
  final wav = pcm16ToWav(pcmBytes, sampleRate: commonRate, channels: 1);

  final coverage = tracks.map((track) => track.senderId).toList()..sort();
  final durationMs = commonRate == 0 ? 0 : (outLen * 1000) ~/ commonRate;
  // Complete when every source was mixed and the mix holds exactly the
  // expected SPEAKERS. A speaker can span several sources once a call has moved
  // between their devices (client#9173), so it is speakers that are counted;
  // the divisor above is the speaker count too, so one speaker's chain never
  // weighs more than the other speaker.
  final complete =
      !anySkipped &&
      tracks.map((track) => track.senderId).toSet().length == expectedUsers &&
      !truncated;

  return CallAudioMergeResult(
    wav: wav,
    durationMs: durationMs,
    sampleRate: commonRate,
    channels: 1,
    sourceCoverage: coverage,
    complete: complete,
  );
}

CallAudioMergeResult _emptyResult(int rate) => CallAudioMergeResult(
  wav: pcm16ToWav(Uint8List(0), sampleRate: rate, channels: 1),
  durationMs: 0,
  sampleRate: rate,
  channels: 1,
  sourceCoverage: const [],
  complete: false,
);

/// A parsed, kept half: its rate and its samples plus its timeline anchor.
class _KeptHalf {
  final int sampleRate;
  final Int16List samples;
  final int fileStartSfuMs;
  final String senderId;

  const _KeptHalf({
    required this.sampleRate,
    required this.samples,
    required this.fileStartSfuMs,
    required this.senderId,
  });
}

/// A half resampled to the common rate and positioned by its sample delay.
class _Track {
  final Int16List samples;
  final int delay;
  final String senderId;

  const _Track({
    required this.samples,
    required this.delay,
    required this.senderId,
  });
}

/// The fields of a WAV needed to mix it.
class _ParsedWav {
  final int sampleRate;
  final Int16List samples;

  const _ParsedWav(this.sampleRate, this.samples);
}

/// Parses a WAV, returning its rate and little-endian PCM16 samples, or null if
/// it is not a readable PCM16 mono WAV.
///
/// Walks the RIFF chunk list (rather than assuming a fixed 44-byte header) so a
/// foreign layout is handled, and reads every sample with an explicit
/// little-endian [ByteData.getInt16] — never `Int16List.view`, whose endianness
/// is the host's and breaks on the web.
_ParsedWav? _parsePcm16MonoWav(Uint8List bytes) {
  if (bytes.length < 12) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  if (!_tagEquals(bytes, 0, 'RIFF') || !_tagEquals(bytes, 8, 'WAVE')) {
    return null;
  }

  // Bound the chunk walk by the declared RIFF payload so trailing bytes past the
  // container are never parsed as chunks. Fall back to the buffer length when the
  // declared size is implausible or overruns the buffer, and never read past the
  // buffer either way.
  final declaredRiff = data.getUint32(4, Endian.little);
  final riffEnd = (declaredRiff >= 4 && 8 + declaredRiff <= bytes.length)
      ? 8 + declaredRiff
      : bytes.length;

  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLen;

  var offset = 12;
  while (offset + 8 <= riffEnd) {
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final bodyStart = offset + 8;
    if (_tagEquals(bytes, offset, 'fmt ')) {
      // A PCM `fmt ` chunk is at least 16 bytes; read its fields only when the
      // chunk actually declares and contains them, so a short/foreign chunk is
      // rejected rather than read from the following chunk's bytes.
      if (chunkSize >= 16 && bodyStart + 16 <= riffEnd) {
        audioFormat = data.getUint16(bodyStart, Endian.little);
        channels = data.getUint16(bodyStart + 2, Endian.little);
        sampleRate = data.getUint32(bodyStart + 4, Endian.little);
        bitsPerSample = data.getUint16(bodyStart + 14, Endian.little);
      }
    } else if (_tagEquals(bytes, offset, 'data')) {
      dataOffset = bodyStart;
      // Clamp a data chunk that overruns the container to what is present, so a
      // truncated blob yields the samples it has and never an out-of-range read.
      final available = riffEnd - bodyStart;
      dataLen = chunkSize <= available ? chunkSize : available;
    }
    // Chunks are word-aligned: an odd body is padded to even.
    var advance = chunkSize;
    if (advance.isOdd) {
      advance += 1;
    }
    offset = bodyStart + advance;
  }

  if (audioFormat != 1 || channels != 1 || bitsPerSample != 16) {
    return null;
  }
  if (sampleRate == null || sampleRate <= 0) {
    return null;
  }
  if (dataOffset == null || dataLen == null) {
    return null;
  }

  // Inputs are this call's own per-device recordings, already bounded by the
  // recording duration ceiling (see the recording design's memory section), so
  // the full parse is the accepted footprint; the OUTPUT cap below trims a call
  // that runs past the ceiling. (Defending against a maliciously oversized
  // FOREIGN blob is a v1 non-goal — the merger operates on our own recordings.)
  final sampleCount = dataLen ~/ 2;
  final samples = Int16List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = data.getInt16(dataOffset + i * 2, Endian.little);
  }
  return _ParsedWav(sampleRate, samples);
}

bool _tagEquals(Uint8List bytes, int offset, String tag) {
  if (offset + tag.length > bytes.length) {
    return false;
  }
  for (var i = 0; i < tag.length; i++) {
    if (bytes[offset + i] != tag.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

/// Half-length (input samples each side) of the resampling kernel: 2 * this =
/// 16 taps per phase.
const _resampleHalfLen = 8;

/// Kaiser window shape parameter (~80 dB stop-band).
const _kaiserBeta = 8.0;

/// Upsamples [input] by an exact integer [factor] with a windowed-sinc
/// (Kaiser) polyphase kernel — the reconstruction filter for upsampling, so no
/// separate anti-alias pass is needed.
///
/// Phase 0 copies the input sample verbatim (an exact passthrough), so the
/// original samples are preserved BIT-FOR-BIT at output positions that are
/// multiples of [factor]. The intermediate phases use the windowed-sinc kernel,
/// whose coefficients are normalized to unity DC gain (a constant input maps to
/// that constant); those interpolated samples reproduce the reference swresample
/// IN KIND (inaudible for speech), not bit-for-bit. Interpolated output is
/// clamped to the PCM16 representable range to bound sinc overshoot before it is
/// stored as Int16 — a range guard on the filter, not a limiter on the mix.
Int16List _upsampleInteger(Int16List input, int factor) {
  if (factor <= 1) {
    return input;
  }
  final taps = 2 * _resampleHalfLen;
  final i0Beta = _besselI0(_kaiserBeta);
  final banks = List<Float64List>.generate(factor, (phase) {
    final frac = phase / factor;
    final coeffs = Float64List(taps);
    var sum = 0.0;
    for (var t = 0; t < taps; t++) {
      final j = t - _resampleHalfLen + 1; // input offset from the base sample
      final offset =
          j - frac; // distance to the interpolation point, in samples
      final coeff = _sinc(offset) * _kaiser(offset, _resampleHalfLen, i0Beta);
      coeffs[t] = coeff;
      sum += coeff;
    }
    if (sum != 0.0) {
      for (var t = 0; t < taps; t++) {
        coeffs[t] /= sum;
      }
    }
    return coeffs;
  });

  final n = input.length;
  final out = Int16List(n * factor);
  for (var m = 0; m < out.length; m++) {
    final base = m ~/ factor;
    final phase = m % factor;
    if (phase == 0) {
      // Phase 0 is an exact passthrough: an output sample at a multiple of the
      // factor IS the original input sample, copied verbatim (no kernel/rounding).
      out[m] = input[base];
      continue;
    }
    final coeffs = banks[phase];
    var acc = 0.0;
    for (var t = 0; t < taps; t++) {
      final idx = base + (t - _resampleHalfLen + 1);
      if (idx >= 0 && idx < n) {
        acc += input[idx] * coeffs[t];
      }
    }
    out[m] = _clampInt16(acc.round());
  }
  return out;
}

double _sinc(double x) {
  if (x == 0.0) {
    return 1.0;
  }
  final px = pi * x;
  return sin(px) / px;
}

/// Kaiser window over the support [-halfLen, halfLen] (offset in input samples).
double _kaiser(double offset, int halfLen, double i0Beta) {
  final ratio = offset / halfLen;
  if (ratio <= -1.0 || ratio >= 1.0) {
    return 0.0;
  }
  return _besselI0(_kaiserBeta * sqrt(1.0 - ratio * ratio)) / i0Beta;
}

/// Modified Bessel function of the first kind, order 0, by its power series.
double _besselI0(double x) {
  var sum = 1.0;
  var term = 1.0;
  final quarterXsq = (x * x) / 4.0;
  for (var k = 1; k < 30; k++) {
    term *= quarterXsq / (k * k);
    sum += term;
    if (term < sum * 1e-12) {
      break;
    }
  }
  return sum;
}

int _clampInt16(int value) {
  if (value < -32768) {
    return -32768;
  }
  if (value > 32767) {
    return 32767;
  }
  return value;
}
