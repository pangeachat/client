/// One dosage message-envelope signal: a single sent learner message reduced to
/// counts and identifiers, with no content. The wire body is the verbatim
/// [toJson] under `events[]` — the BFF ingest is `extra="forbid"`, so this
/// carries EXACTLY the six contract keys and no `sender` (identity is bound
/// server-side from the bearer token) and no `lang_source`.
class DosageMessageEvent {
  /// Server-enforced ceilings (mirror the `dosage_message_events` CHECKs). We
  /// clamp client-side so an outlier message is a capped count, never a 422.
  static const int maxTokenCount = 2000;
  static const int maxCharCount = 65536;

  final String roomId;
  final String msgId;
  final DateTime ts;
  final int tokenCount;
  final int charCount;

  /// Detected language of the message when known (from tokenization), else
  /// null. Never invented from an assumed room language.
  final String? langCode;

  const DosageMessageEvent({
    required this.roomId,
    required this.msgId,
    required this.ts,
    required this.tokenCount,
    required this.charCount,
    required this.langCode,
  });

  /// Whitespace-token fallback for a message that was sent without
  /// tokenization (e.g. a pasted or non-L2 message). Empty body => 0.
  static int whitespaceTokenCount(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  /// Builds the signal from a just-sent message. [tokenCount] is the already
  /// computed token count when the message was tokenized (else null → the
  /// whitespace fallback). Counts are clamped to the server ceilings.
  factory DosageMessageEvent.fromSentMessage({
    required String roomId,
    required String msgId,
    required DateTime ts,
    required String body,
    int? tokenCount,
    String? langCode,
  }) {
    final int tokens = tokenCount ?? whitespaceTokenCount(body);
    return DosageMessageEvent(
      roomId: roomId,
      msgId: msgId,
      ts: ts.toUtc(),
      tokenCount: tokens.clamp(0, maxTokenCount),
      charCount: body.length.clamp(0, maxCharCount),
      langCode: langCode,
    );
  }

  Map<String, dynamic> toJson() => {
    "room_id": roomId,
    "msg_id": msgId,
    "ts": ts.toUtc().toIso8601String(),
    "token_count": tokenCount,
    "char_count": charCount,
    "lang_code": langCode,
  };
}
