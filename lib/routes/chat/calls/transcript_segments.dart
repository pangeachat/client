import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// One readable stretch of a speaker's speech.
///
/// Text only. Word timings are used to CUT segments (below) and are then
/// dropped rather than stored: per-speaker sections order by position, so
/// offsets buy nothing to read them back, and persisted offsets would disclose
/// a speaker's rhythm, pauses and silences to anyone who can read the room —
/// which is more than "your words are saved" promises.
class TranscriptSegment {
  final String text;

  const TranscriptSegment(this.text);

  Map<String, dynamic> toJson() => {'text': text};

  static TranscriptSegment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String) return null;
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : TranscriptSegment(trimmed);
  }

  @override
  bool operator ==(Object other) =>
      other is TranscriptSegment && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TranscriptSegment($text)';
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
List<TranscriptSegment> buildSegments(
  List<SpeechToTextResponseModel> ordered, {
  Duration pause = kUtterancePause,
}) {
  final segments = <TranscriptSegment>[];

  for (final result in ordered) {
    if (!result.hasUsableTranscript) continue;
    final transcript = result.transcript;
    final timings = transcript.wordTimings;

    if (timings == null || timings.isEmpty) {
      _add(segments, transcript.text);
      continue;
    }

    // A word whose start the provider omitted cannot open a gap, so it joins
    // whatever is being built rather than being dropped or guessed at.
    final words = <String>[];
    int? previousEnd;
    final countBefore = segments.length;

    for (final timing in timings) {
      final start = timing.startTimeMs;
      final gapOpens =
          start != null &&
          previousEnd != null &&
          start - previousEnd >= pause.inMilliseconds;

      if (gapOpens && words.isNotEmpty) {
        _add(segments, words.join(' '));
        words.clear();
      }

      final word = timing.word.trim();
      if (word.isNotEmpty) words.add(word);
      // An unknown end makes the NEXT gap unmeasurable. Keeping the previous
      // word's end here measured that gap from the wrong place and split an
      // utterance that had no pause in it.
      previousEnd = timing.endTimeMs;
    }

    if (words.isNotEmpty) _add(segments, words.join(' '));

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
      _add(segments, transcript.text);
      continue;
    }

    // Every timing was empty or whitespace, which would silently lose a chunk
    // the provider did read. The chunk's own text is the fallback.
    //
    // Judged PER CHUNK. Asking whether `segments` is empty overall meant a
    // later chunk with all-blank timings was dropped whenever an earlier chunk
    // had produced anything -- silently losing speech, and only in calls long
    // enough to have a second chunk.
    if (segments.length == countBefore) _add(segments, transcript.text);
  }

  return List.unmodifiable(segments);
}

void _add(List<TranscriptSegment> into, String text) {
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) into.add(TranscriptSegment(trimmed));
}
