import 'dart:math';
import 'dart:typed_data';

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
  Uint8List toWav() {
    const headerSize = 44;
    final out = Uint8List(headerSize + pcm.lengthInBytes);
    final view = ByteData.sublistView(out);

    void ascii(int offset, String tag) {
      for (var i = 0; i < tag.length; i++) {
        out[offset + i] = tag.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    view.setUint32(4, out.length - 8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little); // fmt chunk size
    view.setUint16(20, 1, Endian.little); // PCM, uncompressed
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * _bytesPerFrame, Endian.little);
    view.setUint16(32, _bytesPerFrame, Endian.little);
    view.setUint16(34, 16, Endian.little); // bits per sample
    ascii(36, 'data');
    view.setUint32(40, pcm.lengthInBytes, Endian.little);
    out.setRange(headerSize, out.length, pcm);
    return out;
  }
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
  int get _maxFrames => sampleRate * maxDuration.inMilliseconds ~/ 1000;
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

    // Nothing was said here, so there is nothing to send. A stretch of a call
    // where this learner is listening carries no words, and uploading it buys a
    // transcription of silence: the bytes cost bandwidth on a phone, the
    // request costs money, and the answer is always empty. In an ordinary
    // conversation each side is quiet for roughly half of it.
    //
    // Measured over the whole chunk rather than trusted to the running count
    // above, which only sees whole analysis windows — the remainder at the end
    // has never been looked at, and speech that fell entirely inside it would
    // be thrown away.
    if (_hasNothingInIt(pcm)) return null;

    return PcmChunk(
      pcm: pcm,
      sampleRate: sampleRate,
      channels: channels,
      index: _nextIndex++,
    );
  }

  /// Whether a whole chunk is below the level speech reaches.
  ///
  /// The same threshold the split points use, applied to everything at once.
  /// Deliberately a low bar: it is there to recognise a microphone in a quiet
  /// room, not to judge how loudly somebody spoke.
  bool _hasNothingInIt(Uint8List pcm) {
    final samples = pcm.lengthInBytes ~/ 2;
    if (samples == 0) return true;
    final view = ByteData.sublistView(pcm);
    var sumSquares = 0.0;
    for (var i = 0; i < samples; i++) {
      final v = view.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += v * v;
    }
    return sqrt(sumSquares / samples) < silenceThreshold;
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
