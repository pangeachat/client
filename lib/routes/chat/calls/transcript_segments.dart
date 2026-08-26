import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// One readable stretch of a speaker's speech, and when it was said.
///
/// This class used to carry a written promise that it held text ONLY — that
/// word timings were used to cut segments and then dropped, because
/// per-speaker sections order by position so offsets bought nothing to read
/// them back. That premise has expired rather than been forgotten: an offset is
/// now what puts a turn in the conversation, which is exactly what the
/// turn-by-turn transcript changed.
///
/// The consequence the old promise named still stands, and the owner has
/// accepted it. Per-segment positions are coarser than word timings, but they
/// still disclose when each turn happened and, by subtraction, how long the
/// gaps were. The ruling was that seeing the pause is fine, and that somebody
/// working one out by subtracting two times is fine, but that we do not
/// deliberately show it — hence per-turn times on screen and no gap or pause
/// element anywhere.
///
/// What is still not persisted is the per-word detail. ONE offset per segment
/// is stored, and it is the number the segment boundary was already chosen on.
class TranscriptSegment {
  final String text;

  /// When this stretch of speech began, in absolute Unix milliseconds, or null
  /// when it cannot be placed in time.
  ///
  /// Null is a first-class answer rather than a failure. A missing or unusable
  /// position costs the SHAPE of the screen — the call falls back to the
  /// per-speaker view — and never a word of what was said. See [fromJson] for
  /// what is accepted off the wire, and [buildSegments] for when one is
  /// produced at all.
  final int? atMs;

  const TranscriptSegment(this.text, {this.atMs});

  Map<String, dynamic> toJson() => {
    'text': text,
    if (atMs != null) 'at_ms': atMs,
  };

  /// One past the largest position that survives a JSON round trip.
  ///
  /// JSON numbers are doubles, and the largest integer a double holds exactly
  /// is 2^53 - 1. Anything at or beyond this is not a time this writer produced.
  static const atMsCeiling = 9007199254740992;

  static TranscriptSegment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // A bad position costs a position, never words. `text` alone decides
    // whether this segment exists, so a malformed, negative, out-of-range or
    // absent `at_ms` leaves it present, readable and simply unplaced.
    //
    // Both halves of that matter. Rejecting the segment instead would drop
    // speech and mark the half shortened, which is a reader-side lie about what
    // the writer sent; and accepting loose numbers would let hostile content
    // satisfy the render gate with fabricated positions.
    final at = raw['at_ms'];
    return TranscriptSegment(
      trimmed,
      atMs: at is int && at >= 0 && at < atMsCeiling ? at : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TranscriptSegment && other.text == text && other.atMs == atMs;

  @override
  int get hashCode => Object.hash(text, atMs);

  @override
  String toString() => atMs == null
      ? 'TranscriptSegment($text)'
      : 'TranscriptSegment($text @$atMs)';
}

/// One chunk's frozen transcription, together with where its audio sat.
///
/// The two travel in one object rather than as two lists, because they are only
/// ever correct together. The sink holds both halves keyed by chunk index and
/// pairs them BY KEY; a chunk whose transcription failed has a position and no
/// response, so lists zipped by position would slide every later chunk's start
/// time onto the wrong words.
class TranscribedChunk {
  final SpeechToTextResponseModel result;

  /// When this chunk's audio began, in absolute Unix milliseconds.
  final int startedAtMs;

  /// How long this chunk's audio runs.
  ///
  /// The ceiling the positioning rule measures word timings against. A timing
  /// past the end of the audio it claims to describe is not a position, it is a
  /// number.
  final int durationMs;

  const TranscribedChunk({
    required this.result,
    required this.startedAtMs,
    required this.durationMs,
  });
}

/// How long a gap between two words has to be before they are read as separate
/// utterances.
///
/// A conversational pause, not a breath. Too small and every hesitation starts
/// a new line; too large and a 45-second chunk stays one wall of text, which is
/// the thing this exists to prevent.
const kUtterancePause = Duration(milliseconds: 900);

final _whitespace = RegExp(r'\s+');

/// A chunk's text, normalised for comparison ONLY by case and whitespace.
///
/// Deliberately forgiving nothing else. Three cleverer rules each let speech
/// through altered: a character ratio missed a short word dropped off a long
/// one; a word count matched "pay bob today" against timings for
/// [pay, alice, today] and fabricated "alice"; stripping punctuation made
/// "he'll" equal "hell", and stripping it only at word edges still made "C++"
/// equal "C".
///
/// So the rule is exact. If the timings do not reconstruct the chunk, the
/// chunk's own text is used. The cost is coarser segmentation whenever a
/// provider omits punctuation from its word list -- a readability cost, paid
/// knowingly, because the alternative is a transcript that quietly says
/// something the learner did not.
String _words(String text) =>
    text.toLowerCase().trim().split(_whitespace).join(' ');

/// Cuts one call's frozen responses into readable segments.
///
/// [ordered] must already be in the order the speaker said them —
/// `CallTranscriptSink` keys responses by `PcmChunk.index` and reads them back
/// sorted, precisely because transcription is async and a later chunk can come
/// back first, so callers pass that order through rather than re-deriving it.
///
/// Word timings are used where the provider supplied them and IGNORED where it
/// did not: they are documented as nullable and never fabricated, so a response
/// without them yields one segment for the whole chunk rather than no segment
/// at all. Losing the finer cut is a readability cost; dropping the words would
/// be a correctness one.
///
/// A segment carries a POSITION only when it has a real one. A whole-chunk
/// fallback never does — see [_isWellFormedSequence] for the other half of that
/// rule. An earlier version gave the fallbacks an offset of zero and called it
/// exact, and it is not: a ninety-second chunk can open with silence, so zero
/// is the CHUNK's position passed off as the SPEECH's, and interleaving the
/// other speaker against it would be confidently wrong.
List<TranscriptSegment> buildSegments(
  List<TranscribedChunk> ordered, {
  Duration pause = kUtterancePause,
}) {
  final segments = <TranscriptSegment>[];

  for (final chunk in ordered) {
    final result = chunk.result;
    if (!result.hasUsableTranscript) continue;
    final transcript = result.transcript;
    final timings = transcript.wordTimings;

    if (timings == null || timings.isEmpty) {
      _add(segments, transcript.text, null);
      continue;
    }

    // Decided ONCE per chunk, before anything is cut. The cut runs either way:
    // a chunk that cannot be positioned still gets whatever finer segmentation
    // its timings buy, it simply does not claim to know when any of it
    // happened.
    final placeable = _isWellFormedSequence(timings, chunk.durationMs);

    // A word whose start the provider omitted cannot open a gap, so it joins
    // whatever is being built rather than being dropped or guessed at.
    final words = <String>[];

    // The end of the previous DISPLAYED word, never of the previous timing.
    //
    // A blank entry between two words otherwise absorbs the gap between them.
    // `hello` at 0-100, a blank at 100-3000 and `world` at 3000-3100 is a
    // perfectly ordered partition of the chunk, and `world`'s gap then measures
    // 3000 - 3000 = 0: no cut, one segment stamped at 0 holding a word spoken
    // three seconds in — and the other speaker's reply at 2.5s renders after
    // it. The timings there are sound; the CUT was wrong. The pause that
    // matters is the one between two words a reader can SEE, which is what this
    // was always trying to measure, and blank entries then affect nothing at
    // all.
    int? previousEnd;

    // Where the segment being built starts, taken when its first word enters
    // the buffer. At the cut the value in hand belongs to the segment being
    // OPENED, not to the one being emitted. Left null for a chunk that cannot
    // be placed, which is what leaves its segments unpositioned.
    int? openedAt;

    final countBefore = segments.length;

    for (final timing in timings) {
      final start = timing.startTimeMs;
      final gapOpens =
          start != null &&
          previousEnd != null &&
          start - previousEnd >= pause.inMilliseconds;

      if (gapOpens && words.isNotEmpty) {
        _add(segments, words.join(' '), _positionOf(chunk, openedAt));
        words.clear();
        openedAt = null;
      }

      final word = timing.word.trim();
      if (word.isEmpty) continue;
      if (words.isEmpty && placeable) openedAt = start;
      words.add(word);
      // An unknown end makes the NEXT gap unmeasurable. Keeping the previous
      // word's end here measured that gap from the wrong place and split an
      // utterance that had no pause in it.
      previousEnd = timing.endTimeMs;
    }

    if (words.isNotEmpty) {
      _add(segments, words.join(' '), _positionOf(chunk, openedAt));
    }

    // Timings that account for materially less than the transcript are not a
    // finer cut of it, they are a partial one -- and keeping only what they
    // covered silently drops the rest. "hello world" timed as ["hello"] must
    // not become "hello".
    // The timings must reconstruct the transcript EXACTLY, word for word.
    //
    // Counting words was still a proxy, and proxies here fail in the worst
    // direction available. Timings [pay, alice, today] against the text
    // "pay bob today" have the same word count, so a count check passed them
    // and the output became "pay alice today" -- losing a word AND inventing
    // one. A coarse transcript is a readability problem; a fabricated one is
    // put in a learner's mouth and read as evidence of what they said.
    final rebuilt = segments
        .skip(countBefore)
        .map((segment) => segment.text)
        .join(' ');
    if (_words(rebuilt) != _words(transcript.text)) {
      segments.removeRange(countBefore, segments.length);
      // Unpositioned, even when the timings were a flawless sequence. This is
      // the fallback that proves the never-position-a-fallback rule has to be
      // its own rule rather than a consequence of the sequence check: the
      // timings here can be complete and sane and it still fires, because they
      // described DIFFERENT WORDS than the transcript did — so a position taken
      // from them would describe the timed subset, not the text being shown.
      _add(segments, transcript.text, null);
      continue;
    }

    // Every timing was empty or whitespace, which would silently lose a chunk
    // the provider did read. The chunk's own text is the fallback.
    //
    // Judged PER CHUNK. Asking whether `segments` is empty overall meant a
    // later chunk with all-blank timings was dropped whenever an earlier chunk
    // had produced anything -- silently losing speech, and only in calls long
    // enough to have a second chunk.
    if (segments.length == countBefore) _add(segments, transcript.text, null);
  }

  return List.unmodifiable(segments);
}

/// Whether a chunk's timings are a WELL-FORMED SEQUENCE, which is the only
/// thing that lets its segments be positioned:
///
/// > Every timing carries both a start and an end, and
/// > `0 <= start0 <= end0 <= start1 <= end1 <= ... <= duration`.
///
/// No exemptions. Not the last word's end, not blank words, not "the ones the
/// cut actually uses".
///
/// Six review rounds in a row found the same thing: another shape of malformed
/// provider timing the rule of the day did not cover. Words out of order. A
/// valid blank that erased a pause. A word whose start was fine and whose end
/// was hours away. An interior word with no start at all, whose only timing
/// said it ended before the word before it began. Each round described one more
/// property "usable" timings must have, and each round there was another.
///
/// The mistake was trying to CHARACTERISE usable timings. This does not: it
/// requires them to be a valid ordered partition of the chunk's own time, which
/// is what the cut reads them as anyway. Everything downstream then follows
/// without a case analysis — a segment's first word start is necessarily the
/// earliest speech in it, every gap is measured from a real end, and nothing
/// lies outside the chunk.
///
/// The cost is real and is accepted: one absent end anywhere in a chunk makes
/// that chunk unpositioned, and one unpositioned chunk drops the whole CALL
/// back to the per-speaker view. Three earlier versions carved out exemptions
/// to avoid that, and all three carve-outs were where the next hole was found.
/// If providers turn out to omit ends routinely, that will show up as calls
/// rendering per-speaker — a visible, measurable fact to revisit on, rather
/// than a guess to design around now.
bool _isWellFormedSequence(List<WordTiming> timings, int durationMs) {
  // Starts at zero, which is also what rejects a negative first start.
  var previousEnd = 0;
  for (final timing in timings) {
    final start = timing.startTimeMs;
    final end = timing.endTimeMs;
    if (start == null || end == null) return false;
    if (start < previousEnd || end < start || end > durationMs) return false;
    previousEnd = end;
  }
  return true;
}

/// Where a segment opening [offsetInChunk] into [chunk] sits on the call's
/// clock, or null when the chunk could not be placed.
int? _positionOf(TranscribedChunk chunk, int? offsetInChunk) =>
    offsetInChunk == null ? null : chunk.startedAtMs + offsetInChunk;

void _add(List<TranscriptSegment> into, String text, int? atMs) {
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) into.add(TranscriptSegment(trimmed, atMs: atMs));
}
