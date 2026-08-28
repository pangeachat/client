import 'dart:math';
import 'dart:typed_data';

import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

/// The audio to send for one chunk, and where it sat inside that chunk.
///
/// The three parts travel in one object because they are only ever correct
/// together. [wav] is what goes to the provider, [startMs] is the offset into
/// the chunk it was taken from, and [durationMs] is how long it runs. A caller
/// that moved the audio without moving its position would place every word the
/// provider returns at a moment nobody spoke.
class TrimmedChunkAudio {
  final Uint8List wav;

  /// Offset into the chunk where this audio begins. Zero when the whole chunk
  /// is being sent.
  final int startMs;

  /// How long the audio in [wav] runs — the length actually sent, never the
  /// chunk's own length. It is the ceiling a provider's word timings are
  /// measured against, so it has to describe the audio those timings came from.
  final int durationMs;

  const TrimmedChunkAudio({
    required this.wav,
    required this.startMs,
    required this.durationMs,
  });
}

/// The constants the trim decides on.
///
/// All injectable, and every one of them calibrated against a SINGLE recording.
/// Named and grouped here rather than scattered as literals so a second sample
/// can retune the detector without rearchitecting anything around it.
class SpeechTrimSettings {
  /// Normalised autocorrelation at or above which a frame counts as voiced.
  ///
  /// The measurement this design turns on. On the reference recording the
  /// longest run of voiced frames in the non-speech region falls from 260ms at
  /// 0.55 to 180ms at 0.65 and 140ms at 0.75, while speech keeps twenty-odd
  /// runs past 200ms throughout. 0.70 sits in the middle of that plateau.
  final double voicedPeak;

  /// A contiguous voiced run at least this long is speech on its own.
  ///
  /// What keeps SHORT ANSWERS. "haan", "nahi", "yes", "okay" are the
  /// credit-bearing utterances a learner produces, and a rule that only
  /// recognised sustained conversation would drop every one of them. There is
  /// deliberately no minimum span length anywhere in this file.
  ///
  /// The thinnest margin in the design: 200ms sits above a measured noise
  /// ceiling of 140-180ms and below the voicing in the shortest real words.
  final Duration minVoicedRun;

  /// Fraction of frames in [smoothWindow] that must be voiced for the stretch
  /// to count as sustained speech.
  final double speechFraction;

  /// The window [speechFraction] is measured over.
  ///
  /// Long enough that the scattered voicing in room noise cannot fill it.
  /// Insensitive in practice: with [voicedPeak] at 0.70, every combination of
  /// 1000-3000ms against 0.25-0.60 picked the same stretch of the reference
  /// recording to within a second.
  final Duration smoothWindow;

  /// Added to each end of the span.
  ///
  /// The one number here whose error DELETES speech rather than costing a
  /// request: an unvoiced onset or coda running further than this past the
  /// nearest voiced frame is clipped. Unvalidated — chosen to cover ordinary
  /// aspirated onsets and sentence-initial fricatives, which run 50-200ms.
  final Duration pad;

  /// Below this, a chunk is sent whole and never analysed.
  ///
  /// The defect this file exists for needs a LOT of non-speech to swamp a
  /// little speech, and a short chunk cannot be swamped. It is also where a
  /// one-word answer lives, so it is the wrong place to be clever.
  final Duration minTrimmable;

  /// A span covering more than this fraction of its chunk is not worth taking.
  ///
  /// A marginal trim saves little and carries all of the clipping risk, so the
  /// whole chunk goes instead.
  final double keepWholeAbove;

  /// A chunk with no voiced frames is only suppressed if its loudest sustained
  /// stretch scores below this.
  ///
  /// Audio that is loud but aperiodic is audio we do not UNDERSTAND, not audio
  /// we know to be empty — whispered and wholly unvoiced speech look exactly
  /// like that. This uses level, but only ever to refuse to suppress, which is
  /// the safe direction.
  ///
  /// Measured over the LOUDEST WINDOW rather than the whole chunk, for the same
  /// reason the voicing test is: a chunk-wide average cannot tell sparse bursts
  /// apart from continuous sound. It scored a 22s-noise-plus-18s-whisper chunk
  /// at 0.58 against pure noise's 0.46 — eighteen seconds of speech separated
  /// from room noise by twelve points, and on the wrong side of any threshold
  /// that still suppressed the noise. The same cases measured over the loudest
  /// three seconds score 0.39-0.72 for non-speech and 0.97-0.99 for speech.
  final double skipBelowLoud;

  /// The stretch [skipBelowLoud] is measured over.
  final Duration loudWindow;

  /// How far above a chunk's own tenth-percentile level a window has to be to
  /// count as loud. Relative to the chunk, so it carries across devices.
  final double loudMultiple;

  /// The level, as a fraction of full scale, above which a chunk's own QUIETEST
  /// windows are themselves too loud to be silence.
  ///
  /// [loudMultiple] is relative to the chunk's tenth percentile, which silently
  /// assumes the chunk contains a quiet part. A chunk that is steady sound all
  /// the way through — an unbroken whisper, a fricative, a continuous machine —
  /// has its floor sitting at the level of the sound itself, so nothing clears
  /// four times it and the relative measure reports near zero for audio that is
  /// loud everywhere.
  ///
  /// This is the absolute backstop for that degenerate case, and it only ever
  /// REFUSES to suppress. -45 dBFS, against a measured room-noise floor of
  /// about -59 dBFS on the reference recording. **Unvalidated**: no steady
  /// whispered sample exists here to place it against from the other side.
  final double quietFloor;

  const SpeechTrimSettings({
    this.voicedPeak = 0.70,
    this.minVoicedRun = const Duration(milliseconds: 200),
    this.speechFraction = 0.45,
    this.smoothWindow = const Duration(seconds: 2),
    this.pad = const Duration(milliseconds: 300),
    this.minTrimmable = const Duration(seconds: 8),
    this.keepWholeAbove = 0.70,
    this.skipBelowLoud = 0.85,
    this.loudWindow = const Duration(seconds: 3),
    this.loudMultiple = 4.0,
    this.quietFloor = 0.0056,
  });
}

/// The rate the voicing test runs at.
///
/// Pitch lives below 400 Hz, so 4 kHz retains everything the test looks at
/// while cutting the work by the decimation factor squared. Nothing but the
/// voicing test sees this rate.
const _analysisRate = 4000;

/// Analysis frame and step, in milliseconds. Standard pitch-tracking geometry:
/// long enough to hold three periods of the lowest pitch tracked, stepped finely
/// enough to place a boundary within a phoneme.
const _frameMs = 32;
const _hopMs = 20;

/// The pitch band the voicing test searches.
const _minPitchHz = 70;
const _maxPitchHz = 400;

/// Chooses the audio to send for [chunk], or null if it holds no speech.
///
/// Null means CAPTURED BUT SILENT: this device looked at the audio and found
/// nothing said in it, so no request is issued. That is a different fact from a
/// provider reading a chunk as silence — this one is a judgement by a detector
/// calibrated on a single recording — and the sink counts it separately for
/// exactly that reason.
///
/// Every uncertain case resolves toward sending MORE audio. A chunk too short
/// to be swamped, a trim too marginal to be worth its risk, and a chunk that is
/// loud but aperiodic all come back whole.
TrimmedChunkAudio? trimToSpeech(
  PcmChunk chunk, {
  SpeechTrimSettings settings = const SpeechTrimSettings(),
}) {
  final whole = TrimmedChunkAudio(
    wav: chunk.toWav(),
    startMs: 0,
    durationMs: chunk.duration.inMilliseconds,
  );

  final totalMs = chunk.duration.inMilliseconds;
  if (totalMs < settings.minTrimmable.inMilliseconds) return whole;

  final reduced = _reduceToMono(chunk);
  final voiced = _voicedFlags(reduced, settings);
  if (voiced.isEmpty) return whole;

  final span = _speechSpan(voiced, settings, totalMs);

  // ONE rule, whether or not a span was found: is there a sustained stretch of
  // sound OUTSIDE what we are about to send?
  //
  // Asking this only when no span was found left a hole. Voicing false
  // positives are supposed to be the safe direction, and they are not when a
  // span exists: a fan or a hum periodic enough to pass for speech pins a span
  // around ITSELF, and whispered speech elsewhere in the chunk then falls
  // outside it and is cut away -- while the veto that exists to catch exactly
  // that never runs, because a span was found. Measuring what is left OUT
  // covers the no-span case as the same question with nothing kept.
  if (_soundOutside(chunk, settings, span) >= settings.skipBelowLoud) {
    return whole;
  }
  if (span == null) return null;

  final keptMs = span.$2 - span.$1;
  if (keptMs >= settings.keepWholeAbove * totalMs) return whole;

  return _slice(chunk, span.$1, span.$2) ?? whole;
}

/// The chunk as one channel of samples at roughly [_analysisRate].
///
/// Channel selection and decimation in ONE pass, and every offset computed in
/// whole sample frames: a slice landing mid-sample would shift the channel phase
/// and hand the voicing test interleaved nonsense. Each output sample is the
/// mean of a whole number of input frames from ONE channel, which is a crude but
/// real anti-alias lowpass rather than bare subsampling.
///
/// The LOUDEST channel, never the average of them. Averaging is the obvious
/// downmix and it is not safe here: two channels in opposite phase sum to
/// nothing, so a signed mean would hand the voicing test digital silence for a
/// chunk somebody is talking through. Taking one channel whole cannot cancel,
/// and it keeps the waveform intact, which the autocorrelation needs.
({Int16List samples, int rate}) _reduceToMono(PcmChunk chunk) {
  final channels = chunk.channels;
  final frames = chunk.pcm.lengthInBytes ~/ (2 * channels);
  final factor = max(1, chunk.sampleRate ~/ _analysisRate);
  final data = ByteData.view(
    chunk.pcm.buffer,
    chunk.pcm.offsetInBytes,
    chunk.pcm.lengthInBytes,
  );

  var channel = 0;
  if (channels > 1) {
    var loudest = -1.0;
    for (var c = 0; c < channels; c++) {
      var energy = 0.0;
      for (var f = 0; f < frames; f++) {
        final v = data
            .getInt16((f * channels + c) * 2, Endian.little)
            .toDouble();
        energy += v * v;
      }
      if (energy > loudest) {
        loudest = energy;
        channel = c;
      }
    }
  }

  final out = Int16List(frames ~/ factor);
  var o = 0;
  for (var f = 0; f + factor <= frames && o < out.length; f += factor) {
    var sum = 0;
    for (var k = 0; k < factor; k++) {
      sum += data.getInt16(((f + k) * channels + channel) * 2, Endian.little);
    }
    out[o++] = sum ~/ factor;
  }
  // The rate the samples ACTUALLY came out at, not the one that was asked for.
  // A device rate that does not divide evenly still lands here correctly, and
  // every lag bound below is derived from this rather than from the target.
  return (samples: out, rate: chunk.sampleRate ~/ factor);
}

/// Whether each analysis frame is periodic in the pitch band.
///
/// The peak of the cross-correlation normalised by the frame's own energy and
/// the energy of the lagged window. Because it is a RATIO it needs no per-device
/// level calibration, which is what lets the primary decision avoid a level
/// threshold entirely. It is invariant to GAIN — not to additive noise, echo or
/// periodic interference, which produce false VOICING and therefore send more
/// audio rather than less.
List<bool> _voicedFlags(
  ({Int16List samples, int rate}) input,
  SpeechTrimSettings settings,
) {
  final s = input.samples;
  final rate = input.rate;
  final frame = rate * _frameMs ~/ 1000;
  final hop = rate * _hopMs ~/ 1000;
  if (frame < 8 || hop < 1 || s.length < frame) return const [];

  final minLag = max(2, rate ~/ _maxPitchHz);
  final maxLag = min(rate ~/ _minPitchHz, frame - 1);
  if (maxLag <= minLag) return const [];

  final work = Float64List(frame);
  final flags = <bool>[];
  for (var start = 0; start + frame <= s.length; start += hop) {
    var mean = 0.0;
    for (var i = 0; i < frame; i++) {
      mean += s[start + i];
    }
    mean /= frame;

    var energy = 0.0;
    for (var i = 0; i < frame; i++) {
      final v = s[start + i] - mean;
      work[i] = v;
      energy += v * v;
    }
    if (energy <= 0) {
      flags.add(false);
      continue;
    }

    var best = 0.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var num = 0.0;
      var den = 0.0;
      final n = frame - lag;
      for (var i = 0; i < n; i++) {
        final b = work[i + lag];
        num += work[i] * b;
        den += b * b;
      }
      if (den > 0) {
        final r = num / sqrt(energy * den);
        if (r > best) best = r;
      }
    }
    flags.add(best >= settings.voicedPeak);
  }
  return flags;
}

/// First to last speech frame, padded, or null if nothing qualifies.
///
/// A frame is speech on EITHER of two grounds, and the second is the one that
/// keeps short answers: scattered voicing in room noise never fills the long
/// window, but neither does a single real word, so a word is recognised by
/// being an unbroken run instead.
(int, int)? _speechSpan(
  List<bool> voiced,
  SpeechTrimSettings settings,
  int totalMs,
) {
  final n = voiced.length;
  final speech = List<bool>.filled(n, false);

  final window = max(1, settings.smoothWindow.inMilliseconds ~/ _hopMs);
  if (n >= window) {
    var count = 0;
    for (var i = 0; i < window; i++) {
      if (voiced[i]) count++;
    }
    for (var i = 0; i + window <= n; i++) {
      if (i > 0) {
        if (voiced[i - 1]) count--;
        if (voiced[i + window - 1]) count++;
      }
      if (count / window >= settings.speechFraction) {
        for (var k = i; k < i + window; k++) {
          speech[k] = true;
        }
      }
    }
  }

  final need = max(1, settings.minVoicedRun.inMilliseconds ~/ _hopMs);
  var run = 0;
  for (var i = 0; i < n; i++) {
    if (voiced[i]) {
      run++;
      if (run >= need) {
        for (var k = i - run + 1; k <= i; k++) {
          speech[k] = true;
        }
      }
    } else {
      run = 0;
    }
  }

  var first = -1;
  var last = -1;
  for (var i = 0; i < n; i++) {
    if (speech[i]) {
      if (first < 0) first = i;
      last = i;
    }
  }
  if (first < 0) return null;

  final pad = settings.pad.inMilliseconds;
  final start = max(0, first * _hopMs - pad);
  final end = min(totalMs, (last + 1) * _hopMs + _frameMs + pad);
  return end > start ? (start, end) : null;
}

/// How loud the chunk's loudest sustained stretch OUTSIDE [span] is, as the
/// fraction of its 20ms windows standing clear of the chunk's own noise floor.
///
/// Corroboration for suppression, and for trimming. A stretch of sound this
/// detector has no explanation for is not a stretch it knows to be empty —
/// whispered and wholly unvoiced speech look exactly like that — so finding one
/// outside what we were going to send means sending the chunk whole instead.
///
/// A null [span] means nothing was going to be kept, so the whole chunk is
/// outside it. That is the same question, not a special case.
///
/// The loudest STRETCH rather than the average, because an average cannot tell
/// a continuous sound from scattered bumps: a chunk half full of room noise and
/// half full of whispering averages to about what a chunk of room noise alone
/// does, and eighteen seconds of speech was thrown away between them.
double _soundOutside(
  PcmChunk chunk,
  SpeechTrimSettings settings,
  (int, int)? span,
) {
  final channels = chunk.channels;
  final frames = chunk.pcm.lengthInBytes ~/ (2 * channels);
  final per = max(1, chunk.sampleRate * _hopMs ~/ 1000);
  if (frames < per) return 0;

  final data = ByteData.view(
    chunk.pcm.buffer,
    chunk.pcm.offsetInBytes,
    chunk.pcm.lengthInBytes,
  );
  final levels = <double>[];
  for (var f = 0; f + per <= frames; f += per) {
    var sum = 0.0;
    for (var i = 0; i < per; i++) {
      final base = (f + i) * channels;
      // Energy SUMMED across channels, never the square of their mean. Two
      // channels in opposite phase average to nothing, and a signed downmix
      // would read a chunk somebody is talking through as digital silence.
      for (var c = 0; c < channels; c++) {
        final v = data.getInt16((base + c) * 2, Endian.little).toDouble();
        sum += v * v;
      }
    }
    levels.add(sqrt(sum / (per * channels)));
  }
  if (levels.isEmpty) return 0;

  final sorted = List<double>.of(levels)..sort();
  final floor = sorted[min(sorted.length - 1, (0.10 * sorted.length).floor())];

  // A chunk whose QUIETEST windows are already loud has no quiet part for the
  // relative bar to stand on, and four times its own floor then measures
  // nothing. Steady sound all the way through is the one shape that breaks the
  // relative test, and it is also a shape a whisper takes.
  if (floor >= settings.quietFloor * 32768.0) return 1;

  final bar = floor * settings.loudMultiple;
  final loud = [for (final level in levels) level > bar ? 1 : 0];
  final window = max(1, settings.loudWindow.inMilliseconds ~/ _hopMs);

  // The loudest [window] run wholly inside `[from, to)`. Zero for a range
  // shorter than the window: a stretch too short to fill it cannot be the
  // SUSTAINED sound this is looking for, and scoring it over whatever it did
  // cover would let one burst beside the span veto every trim.
  double bestIn(int from, int to) {
    if (to - from < window) return 0;
    var count = 0;
    for (var i = from; i < from + window; i++) {
      count += loud[i];
    }
    var best = count;
    for (var i = from + 1; i + window <= to; i++) {
      count += loud[i + window - 1] - loud[i - 1];
      if (count > best) best = count;
    }
    return best / window;
  }

  if (span == null) return bestIn(0, loud.length);

  final firstKept = min(loud.length, span.$1 ~/ _hopMs);
  final lastKept = min(loud.length, (span.$2 + _hopMs - 1) ~/ _hopMs);
  return max(bestIn(0, firstKept), bestIn(lastKept, loud.length));
}

/// The chunk's audio between two offsets, as a WAV, aligned to sample frames.
TrimmedChunkAudio? _slice(PcmChunk chunk, int startMs, int endMs) {
  final bytesPerFrame = 2 * chunk.channels;
  final totalFrames = chunk.pcm.lengthInBytes ~/ bytesPerFrame;

  final firstFrame = (startMs * chunk.sampleRate ~/ 1000).clamp(0, totalFrames);
  final lastFrame = (endMs * chunk.sampleRate ~/ 1000).clamp(0, totalFrames);
  if (lastFrame <= firstFrame) return null;

  final from = chunk.pcm.offsetInBytes + firstFrame * bytesPerFrame;
  final length = (lastFrame - firstFrame) * bytesPerFrame;
  final pcm = Uint8List.view(chunk.pcm.buffer, from, length);

  return TrimmedChunkAudio(
    wav: pcm16ToWav(
      pcm,
      sampleRate: chunk.sampleRate,
      channels: chunk.channels,
    ),
    // Recomputed from the FRAME the slice actually starts at, never from the
    // millisecond that was asked for. The two differ by up to a sample, and the
    // position a word is placed at has to describe the audio that was sent.
    startMs: firstFrame * 1000 ~/ chunk.sampleRate,
    durationMs: (lastFrame - firstFrame) * 1000 ~/ chunk.sampleRate,
  );
}
