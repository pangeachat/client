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
String _words(String text) =>
    text.toLowerCase().trim().split(_whitespace).join(' ');

/// Punctuation at the START or END of a word, and nothing else.
///
/// EDGE-ONLY, because that is the whole of what a transcript legitimately adds:
/// it decorates a word it also encloses in a sentence -- "Hello," for `hello`,
/// "¿Cómo" for `cómo`, Arabic "داخليًا،" for the bare word. A difference INSIDE
/// a word is not decoration, it is a different word: "he'll" is not "hell".
/// Stripping punctuation anywhere, which an earlier version of this did,
/// collapsed exactly that distinction and accepted a timestamp for a word the
/// transcript never contained.
///
/// PUNCTUATION ONLY, never symbols. `+` is a symbol, so "C++" keeps its tail
/// and is correctly refused against a provider's "C" -- the same pair the old
/// exact rule was written to catch.
final _edgePunctuation = RegExp(r'^\p{P}+|\p{P}+$', unicode: true);

/// A word with its decoration removed, for COMPARISON only. Never displayed.
String _core(String word) =>
    word.trim().replaceAll(_edgePunctuation, '').toLowerCase();

/// The transcript's own words, in order.
List<String> _transcriptWords(String text) =>
    text.trim().split(_whitespace).where((w) => w.isNotEmpty).toList();

/// Lines the provider's timings up against the transcript's own words, ONE TO
/// ONE, and hands back the transcript's spelling of each.
///
/// Providers return a punctuation-free word list beside a punctuated
/// transcript: Deepgram is asked for `smart_format` + `punctuate` and its
/// transcript comes back "Hello, मैं ... अभी." while its word list is
/// [hello, मैं, ..., अभी]. Reconstructing the display text from that word list
/// therefore never matched the transcript, which left every real call
/// unpositioned. Measured on the captures on disk: 14/14.
///
/// So the display text comes from the TRANSCRIPT and the timings supply only
/// the WHEN. That also means the punctuation survives into what the learner
/// reads, which assembling from the word list could never do.
///
/// Alignment is deliberately unclever: the counts must match exactly, and each
/// pair must agree once punctuation and case are set aside. Returns null on any
/// disagreement, which drops the chunk to the same unpositioned fallback as
/// before -- never worse than today.
///
/// What the count requirement buys: a provider that re-cuts word boundaries
/// ("therapist" against [the, rapist], "nowhere" against [now, here]) does not
/// line up and is refused, which is the case that could genuinely misattribute
/// speech. What edge-only punctuation buys: "Hello," lines up with `hello`,
/// while "he'll" against "hell" and "C++" against "C" still do not -- those
/// differ INSIDE the word, so they are refused and the chunk falls back
/// unpositioned, exactly as the old exact rule intended.
List<String>? _alignedToTranscript(List<WordTiming> timings, String text) {
  final spoken = <int>[];
  for (var i = 0; i < timings.length; i++) {
    if (timings[i].word.trim().isNotEmpty) spoken.add(i);
  }
  final words = _transcriptWords(text);
  if (spoken.isEmpty || spoken.length != words.length) return null;

  final aligned = List<String>.filled(timings.length, '');
  for (var k = 0; k < spoken.length; k++) {
    if (_core(timings[spoken[k]].word) != _core(words[k])) return null;
    aligned[spoken[k]] = words[k];
  }
  return aligned;
}

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

    // The transcript's own words, one per timing, or null when the two do not
    // line up. Null means this chunk is not cut at all: the timings describe
    // something other than the text being shown, so neither the words nor the
    // positions taken from them can be trusted.
    final aligned = _alignedToTranscript(timings, transcript.text);
    if (aligned == null) {
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

    for (var i = 0; i < timings.length; i++) {
      final timing = timings[i];
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

      // The TRANSCRIPT's spelling, not the provider's word list -- that is what
      // carries the punctuation and the casing a learner reads.
      final word = aligned[i];
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

    // A backstop on THIS loop, not on the provider.
    //
    // Provider disagreement is already refused by `_alignedToTranscript`
    // above, so by the time the cut runs, the words being joined are the
    // transcript's own. What remains is the cut itself losing some: `_add`
    // drops anything that trims to empty, and a mis-sliced buffer would
    // silently shorten a segment. "hello world" emerging as "hello" is a
    // readability bug in this function; putting words a learner never said in
    // front of them would be far worse, and that is what the alignment
    // prevents. Kept because it is nearly free and it fails closed.
    final rebuilt = segments
        .skip(countBefore)
        .map((segment) => segment.text)
        .join(' ');
    if (_words(rebuilt) != _words(transcript.text)) {
      segments.removeRange(countBefore, segments.length);
      // Unpositioned, even when the timings were a flawless sequence: a
      // position taken from a cut that lost text would describe the surviving
      // part, not the text being shown.
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
