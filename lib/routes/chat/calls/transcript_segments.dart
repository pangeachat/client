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
      previousEnd = timing.endTimeMs ?? previousEnd;
    }

    if (words.isNotEmpty) _add(segments, words.join(' '));

    // Every timing was empty or whitespace, which would silently lose a chunk
    // the provider did read. The chunk's own text is the fallback.
    if (words.isEmpty && segments.isEmpty) _add(segments, transcript.text);
  }

  return List.unmodifiable(segments);
}

void _add(List<TranscriptSegment> into, String text) {
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) into.add(TranscriptSegment(trimmed));
}
