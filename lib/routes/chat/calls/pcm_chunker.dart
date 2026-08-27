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

  const PcmChunk({
    required this.pcm,
    required this.sampleRate,
    required this.channels,
    required this.index,
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

  PcmChunker({
    required this.sampleRate,
    required this.channels,
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

  PcmChunk? _cut() {
    if (_framesBuffered == 0) return null;
    final pcm = _buffer.takeBytes();
    _framesBuffered = 0;
    _quietFrames = 0;

    return PcmChunk(
      pcm: pcm,
      sampleRate: sampleRate,
      channels: channels,
      index: _nextIndex++,
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
