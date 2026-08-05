/// Coerce a JSON value to a String, dropping any wrong-typed value to `''`.
/// The relay is trusted to send the D4 shape, but a malformed-yet-valid-JSON
/// frame (wrong field TYPES) must never throw and crash the socket.
String _asString(dynamic value) => value is String ? value : '';

/// Coerce a JSON value to a double, dropping any wrong-typed value to `0`.
double _asDouble(dynamic value) => value is num ? value.toDouble() : 0;

/// One word from a streaming-STT result, with its timing and confidence.
///
/// Mirrors the relay's normalized D4 word shape
/// (`{word, start, end, confidence}`). `start`/`end` are seconds from the start
/// of the stream; the relay already isolates the client from Deepgram's raw
/// envelope, so this model never parses provider-specific fields.
class SttWord {
  const SttWord({
    required this.word,
    required this.start,
    required this.end,
    required this.confidence,
  });

  final String word;
  final double start;
  final double end;
  final double confidence;

  factory SttWord.fromJson(Map<String, dynamic> json) => SttWord(
    word: _asString(json['word']),
    start: _asDouble(json['start']),
    end: _asDouble(json['end']),
    confidence: _asDouble(json['confidence']),
  );
}

/// A streaming-STT transcript update from the relay — an interim `partial`
/// (replace-on-partial) or a settled `segment_final`/`stream_final`
/// (commit-on-final).
///
/// Normalized from the relay's provider-neutral D4 message
/// `{"type":"partial"|"segment_final"|"stream_final","transcript","words":[...]}`.
/// [isFinal] marks a settled result (`segment_final` or `stream_final`);
/// [speechFinal] marks a stream-level speech endpoint (`stream_final`), the
/// primary segment-commit trigger. The public API is unchanged — only the
/// derivation moved from the removed provider-specific booleans to the neutral
/// `type`. This is a display/transport model — a partial is never sent
/// to the embed, bot, or analytics (Phase-2 D10 invariant); only the guarded
/// settled final, or the user's edit of it, is ever sent.
class SttPartial {
  const SttPartial({
    required this.transcript,
    required this.words,
    required this.isFinal,
    required this.speechFinal,
  });

  final String transcript;
  final List<SttWord> words;
  final bool isFinal;
  final bool speechFinal;

  factory SttPartial.fromJson(Map<String, dynamic> json) {
    final rawWords = json['words'];
    final type = json['type'];
    return SttPartial(
      transcript: _asString(json['transcript']),
      words: rawWords is List
          ? rawWords
                .whereType<Map<String, dynamic>>()
                .map(SttWord.fromJson)
                .toList(growable: false)
          : const <SttWord>[],
      // Derive from the neutral type: segment_final/stream_final are settled;
      // only stream_final is a speech endpoint. Keeps the public API identical.
      isFinal: type == 'segment_final' || type == 'stream_final',
      speechFinal: type == 'stream_final',
    );
  }
}
