import 'dart:math';
import 'dart:typed_data';

import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

/// One transcribable piece of a call: raw 16-bit PCM plus the format needed to
/// interpret it.
///
/// A chunk is immutable and positionally identified. [index] is its place in the
/// call, and it is what makes a chunk's transcript safe to freeze — the server
/// keys a result by (capture session, index), so re-delivering the same chunk
/// credits nothing twice.
class PcmChunk {
  /// Interleaved signed 16-bit samples, little-endian.
  final Uint8List pcm;
  final int sampleRate;
  final int channels;

  /// Zero-based position within the capture session.
  final int index;

  /// When this chunk's audio began, in absolute Unix milliseconds.
  ///
  /// Computed from the run's start plus the exact count of frames emitted
  /// before it, never from a clock read at the cut. A cut happens inside a
  /// callback that is already carrying audio captured milliseconds ago, and one
  /// callback can cut several chunks — reading a clock at each would stamp them
  /// all at whatever moment the loop happened to reach them, which is a fact
  /// about CPU time rather than about when anybody spoke.
  final int startedAtMs;

  const PcmChunk({
    required this.pcm,
    required this.sampleRate,
    required this.channels,
    required this.index,
    required this.startedAtMs,
  });

  int get _bytesPerFrame => 2 * channels;

  Duration get duration => Duration(
    microseconds: (pcm.lengthInBytes ~/ _bytesPerFrame) * 1000000 ~/ sampleRate,
  );

  /// The chunk as a WAV file.
  ///
  /// Speech-to-text takes a container, not bare samples, and WAV is the one that
  /// costs nothing to produce: a 44-byte header in front of the bytes we already
  /// hold, with no re-encoding to lose fidelity the transcript depends on.
  /// The chunk as a playable WAV.
  ///
  /// Through the app's own writer rather than a second header of our own: the
  /// bytes the recorder sends and the bytes a call sends should be the same
  /// shape, and one of the two copies would eventually drift.
  Uint8List toWav() =>
      pcm16ToWav(pcm, sampleRate: sampleRate, channels: channels);
}

/// Splits a call's continuous PCM into bounded chunks, cutting at pauses.
///
/// Two reasons this exists rather than recording the call to one file. The
/// speech-to-text route caps a request, so a call of any length arrives in
/// pieces regardless; and transcribing each piece as it completes is what lets a
/// speaker's credit only ever grow, since a frozen chunk's transcript never
/// changes underneath it.
///
/// The cost of chunking is the seam — a word spoken across a boundary can be
/// split. Cutting at silence is what keeps that rare, and the hard ceiling is
/// what keeps the seam bounded when a speaker never pauses.
///
/// Pure and synchronous by design: [add] returns the chunks it completed, so the
/// splitting logic can be tested by feeding it audio, with no streams, timers,
/// or upload machinery in the way.
class PcmChunker {
  final int sampleRate;
  final int channels;

  /// No cut is considered before a chunk reaches this length.
  final Duration targetDuration;

  /// A chunk is cut here whether or not the speaker has paused. Sized to the
  /// upload cap, so it bounds the request rather than the conversation.
  final Duration maxDuration;

  /// The same ceiling expressed in bytes, which is what the route actually
  /// limits. The default is ninety seconds of the capture this app asks for —
  /// 16 kHz, one channel, sixteen bits — so it changes nothing at that rate and
  /// holds the line when a device gives us a higher one.
  final int maxBytes;

  /// How long the audio must stay quiet to count as a pause rather than a
  /// breath between words.
  final Duration minSilence;

  /// RMS below which a window counts as quiet, as a fraction of full scale.
  ///
  /// A threshold rather than a silence detector: a fixed floor over a short
  /// window is enough to find the gap between utterances, and the hard ceiling
  /// covers it when the floor is wrong for a noisy room.
  final double silenceThreshold;

  /// Analysis window for the quiet test. Short enough that a pause is not
  /// averaged away by the speech around it, and independent of the frame sizes
  /// the audio device happens to deliver.
  static const _windowMs = 20;

  final BytesBuilder _buffer = BytesBuilder(copy: true);

  /// Per-channel samples currently buffered.
  int _framesBuffered = 0;

  /// Length of the quiet run at the tail of the buffer, in per-channel samples.
  int _quietFrames = 0;

  /// Samples not yet covered by a completed analysis window.
  final List<int> _window = [];

  /// Where this chunker's numbering starts.
  ///
  /// A chunk index identifies a chunk within the CALL, not within a chunker, and
  /// recording can stop and start again mid-call when another of the learner's
  /// devices takes over and hands back. Restarting at zero would make the second
  /// stretch look like a redelivery of the first, and it would be discarded.
  int _nextIndex;

  /// When this run's audio began, in absolute Unix milliseconds.
  ///
  /// Taken at construction by whoever builds the chunker, and never read from a
  /// clock in here. That is what keeps [add] pure and synchronous, which is
  /// what lets the splitting logic be tested by feeding it audio; and it is
  /// what makes a chunk's position a property of the AUDIO rather than of when
  /// the code got round to looking at it.
  final int runStartedAtMs;

  /// Frames this chunker has already handed out in completed chunks.
  ///
  /// The clock the whole design turns on. A chunk's position is measured in
  /// FRAMES rather than by summing the durations of the chunks before it,
  /// because [PcmChunk.duration] truncates to whole microseconds and then again
  /// to whole milliseconds — and a sum of truncated values drifts a little per
  /// chunk, for as long as the call lasts. A single conversion from an exact
  /// frame count does not drift at all, and costs one multiply per chunk.
  int _framesEmitted = 0;

  /// Audio that existed inside this run and never reached this chunker, in
  /// milliseconds.
  ///
  /// The frame count above is a clock only while every frame arrives. When the
  /// capture path drops a stretch, the frames after it carry on from where the
  /// count left off — so every position derived from it names a moment EARLIER
  /// than the one it was spoken at, by the whole of what went, cumulatively,
  /// for the rest of the run. Adding the gap back into the conversion is what
  /// keeps a position a statement about when somebody spoke.
  ///
  /// It only ever grows through [skip], which cuts first, so no chunk ever
  /// spans a gap: a chunk's own samples are always contiguous, and a word
  /// timing measured from its start still lands where the word was said.
  int _skippedMs = 0;

  PcmChunker({
    required this.sampleRate,
    required this.channels,
    required this.runStartedAtMs,
    int firstIndex = 0,
    this.targetDuration = const Duration(seconds: 45),
    this.maxDuration = const Duration(seconds: 90),
    this.maxBytes = 90 * 16000 * 2,
    this.minSilence = const Duration(milliseconds: 400),
    this.silenceThreshold = 0.02,
  }) : _nextIndex = firstIndex,
       assert(sampleRate > 0),
       assert(channels > 0),
       assert(maxDuration >= targetDuration);

  /// The index the next chunk would take. A caller resuming after a gap passes
  /// this to the chunker that follows.
  int get nextIndex => _nextIndex;

  /// When this run's audio ends, in absolute Unix milliseconds.
  ///
  /// Counted over every frame the chunker has taken in, cut or still buffered,
  /// so the answer is the same before and after a [flush] rather than depending
  /// on which side of one the caller asks from.
  ///
  /// The caller that starts the NEXT run uses this as the floor that run cannot
  /// begin before. Computed here from this chunker's own exact frame count, and
  /// deliberately not recomputed by the caller from the chunks' durations —
  /// that is the truncating sum this replaces.
  int get endedAtMs => _atMs(_framesEmitted + _framesBuffered);

  /// Absolute milliseconds [frames] into this run: the single conversion,
  /// exact frames in and one truncation out, plus whatever the run lost before
  /// this point.
  ///
  /// The gap is added as milliseconds rather than converted to frames and
  /// counted in with the rest. Milliseconds are what was lost: those samples
  /// were never taken in here, and converting them would round them against a
  /// rate that is only this run's by assumption.
  int _atMs(int frames) =>
      runStartedAtMs + _skippedMs + frames * 1000 ~/ sampleRate;

  int get _framesPerWindow => max(1, sampleRate * _windowMs ~/ 1000);
  int get _targetFrames => sampleRate * targetDuration.inMilliseconds ~/ 1000;

  /// The ceiling, in frames, honouring BOTH the time limit and the size one.
  ///
  /// The duration alone was sized for capture at 16 kHz. Android hands over the
  /// audio module's own rate, which is routinely 48 kHz — three times the bytes
  /// for the same ninety seconds — and the route this is sent to caps a
  /// request. Whichever limit is reached first is the one that applies, so the
  /// cap holds at any rate the device happens to use.
  int get _maxFrames {
    final byTime = sampleRate * maxDuration.inMilliseconds ~/ 1000;
    final bySize = maxBytes ~/ (2 * channels);
    return byTime < bySize ? byTime : bySize;
  }

  int get _minSilenceFrames => sampleRate * minSilence.inMilliseconds ~/ 1000;

  /// Adds captured audio, returning any chunks it completed.
  ///
  /// Cuts normally land between calls rather than inside one, which is what
  /// makes the no-sample-lost invariant structural: each frame is appended whole
  /// and never rewritten, so concatenating every emitted chunk with the final
  /// [flush] reproduces the input exactly.
  ///
  /// Input larger than a whole chunk is the exception, and it has to be. A
  /// renderer that batches its callbacks can hand over more audio in one call
  /// than the ceiling allows, and appending it whole would produce a chunk the
  /// upload cap rejects — so oversized input is split at an exact sample
  /// boundary, which preserves the invariant just as well.
  List<PcmChunk> add(Int16List samples) {
    if (samples.isEmpty) return const [];

    final out = <PcmChunk>[];
    var offset = 0;
    while (offset < samples.length) {
      final room = (_maxFrames - _framesBuffered) * channels;
      final take = room < samples.length - offset
          ? room
          : samples.length - offset;
      final slice = Int16List.sublistView(samples, offset, offset + take);
      offset += take;

      _buffer.add(
        Uint8List.view(slice.buffer, slice.offsetInBytes, slice.lengthInBytes),
      );
      _framesBuffered += slice.length ~/ channels;
      _trackQuiet(slice);

      if (_framesBuffered >= _maxFrames ||
          (_framesBuffered >= _targetFrames &&
              _quietFrames >= _minSilenceFrames)) {
        final chunk = _cut();
        if (chunk != null) out.add(chunk);
      }
    }
    return out;
  }

  /// Emits whatever remains, or null if nothing does.
  ///
  /// Called when the call ends. Idempotent: a second flush emits nothing, so a
  /// hangup racing a disconnect cannot produce a duplicate tail.
  PcmChunk? flush() {
    _window.clear();
    return _cut();
  }

  /// Records [ms] of audio this run produced that never arrived here, and cuts
  /// whatever was buffered so that no chunk spans the gap.
  ///
  /// Returns that cut, if there was anything to cut.
  ///
  /// The cut is the point, not a side effect. Merely counting the gap into the
  /// positions would leave the chunk that straddles it holding two stretches
  /// of speech with silence-that-never-happened between them: its own start
  /// would be right, and every word timing after the seam — which a provider
  /// measures from the start of the audio it was given — would be early by the
  /// whole gap, with nothing in the chunk to say where the seam was. Cutting
  /// makes the gap a boundary between chunks, where it can be represented.
  ///
  /// The cost is a short chunk, and the request that carries it, every time
  /// the capture path drops something. That is a far cheaper wrong than a
  /// chunk whose second half is timed from a moment that never existed.
  PcmChunk? skip(int ms) {
    if (ms <= 0) return null;
    // Cleared for the same reason [flush] clears it: the quiet run either side
    // of a gap is not one run, and a window that averaged across the boundary
    // would be measuring audio that is not adjacent.
    _window.clear();
    // BEFORE the gap is counted in, so the chunk being cut is stamped from
    // where it actually began -- which is before the gap, not after it.
    final cut = _cut();
    _skippedMs += ms;
    return cut;
  }

  PcmChunk? _cut() {
    if (_framesBuffered == 0) return null;
    final pcm = _buffer.takeBytes();
    // Stamped from the frames that came BEFORE this chunk, then counted in.
    // Exact frame arithmetic settles the oversized-batch split for free: when
    // one add() cuts several chunks in a single pass, the second sits exactly
    // one chunk's audio after the first, whatever the loop did with CPU time.
    final startedAtMs = _atMs(_framesEmitted);
    _framesEmitted += _framesBuffered;
    _framesBuffered = 0;
    _quietFrames = 0;

    return PcmChunk(
      pcm: pcm,
      sampleRate: sampleRate,
      channels: channels,
      index: _nextIndex++,
      startedAtMs: startedAtMs,
    );
  }

  /// Extends or resets the tail quiet run over the newly added samples.
  void _trackQuiet(Int16List samples) {
    _window.addAll(samples);
    final perWindow = _framesPerWindow * channels;
    var consumed = 0;
    while (_window.length - consumed >= perWindow) {
      final quiet = _isQuiet(consumed, consumed + perWindow);
      _quietFrames = quiet ? _quietFrames + _framesPerWindow : 0;
      consumed += perWindow;
    }
    _window.removeRange(0, consumed);
  }

  bool _isQuiet(int start, int end) {
    var sumSquares = 0.0;
    for (var i = start; i < end; i++) {
      final v = _window[i] / 32768.0;
      sumSquares += v * v;
    }
    return sqrt(sumSquares / (end - start)) < silenceThreshold;
  }
}
