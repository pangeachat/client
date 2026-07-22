import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/repo/tokens_repo.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Tokenizer inputs snapshotted from the AUDIO EVENT (never current user
/// settings), so a repair that runs in a later session -- with a different L1
/// or L2 selected -- still tokenizes the message in its original language.
///
/// Per PHASE1-SPEC D6: `full_text` = the embedded transcript, `lang_code` =
/// `user_stt.lang_code`, `sender_l1` = the event's `speaker_l1`, `sender_l2` =
/// `user_stt.lang_code` (the L2 the message was spoken in).
class SttLangSnapshot {
  final String fullText;
  final String langCode;
  final String senderL1;
  final String senderL2;

  const SttLangSnapshot({
    required this.fullText,
    required this.langCode,
    required this.senderL1,
    required this.senderL2,
  });

  /// Builds the snapshot from the skip-tokenize [baseStt] and the audio event's
  /// `speaker_l1`. [langCode]/[senderL2] both come from the transcript's own
  /// language, so the tokenization is anchored to the message, not the reader.
  factory SttLangSnapshot.fromBaseStt(
    SpeechToTextResponseModel baseStt, {
    required String? speakerL1,
  }) {
    final langCode = baseStt.langCode;
    return SttLangSnapshot(
      fullText: baseStt.transcript.text,
      langCode: langCode,
      senderL1: speakerL1 ?? LanguageKeys.unknownLanguage,
      senderL2: langCode,
    );
  }

  TokensRequestModel toRequest() => TokensRequestModel(
    fullText: fullText,
    langCode: langCode,
    senderL1: senderL1,
    senderL2: senderL2,
  );
}

/// A tokenizer call, injectable so [enrichSttWithTokens] is unit-testable
/// without booting the network stack. Defaults to `TokensRepo.instance.get`.
typedef TokenFetcher =
    Future<Result<TokensResponseModel>> Function(TokensRequestModel request);

/// A `room.sendPangeaEvent` tear-off, injectable so [attachSttRepresentation]
/// is unit-testable without a Matrix `Room`. The real caller passes
/// `room.sendPangeaEvent`, whose signature matches exactly.
typedef PangeaEventSender =
    Future<Event?> Function({
      required Map<String, dynamic> content,
      required String parentEventId,
      required String type,
    });

/// The SINGLE place a decoupled voice message is tokenized. Takes the ORIGINAL
/// skip-tokenize [baseStt] (which already carries transcript/service/confidence/
/// wordsPerHr/word_timings/lang_code -- a bare `/tokenize` call cannot reproduce
/// those), tokenizes its transcript using [snapshot], wraps the returned tokens
/// as [STTToken]s with NULL timings, and returns a result byte-identical to
/// [baseStt] EXCEPT its `stt_tokens` are now populated.
///
/// On a tokenizer error this THROWS the underlying error and never dereferences
/// an error [Result] -- callers catch it and treat the message as still eligible
/// for a later repair (no analytics, no attach).
Future<SpeechToTextResponseModel> enrichSttWithTokens(
  SpeechToTextResponseModel baseStt,
  SttLangSnapshot snapshot, {
  TokenFetcher? tokenFetcher,
}) async {
  final fetch = tokenFetcher ?? TokensRepo.instance.get;
  final result = await fetch(snapshot.toRequest());

  if (result.isError || result.asValue == null) {
    throw result.asError?.error ??
        Exception('SpeechToText: tokenize returned no result');
  }

  final sttTokens = result.asValue!.value.tokens
      // Null timings -- the token timings are unused by any consumer and the
      // background tokenizer has no per-token timing to attach (PHASE1-SPEC D3).
      .map((token) => STTToken(token: token))
      .toList();

  return baseStt.withFirstTranscriptTokens(sttTokens);
}

/// Builds the `pangea.representation` payload that carries a token-rich STT.
/// Pure (no Matrix I/O) so the shape is unit-testable; [attachSttRepresentation]
/// writes it.
PangeaRepresentation buildSttRepresentation(
  SpeechToTextResponseModel richStt,
) => PangeaRepresentation(
  langCode: richStt.langCode,
  text: richStt.transcript.text,
  originalSent: false,
  originalWritten: false,
  speechToText: richStt,
);

/// Writes the token-rich [richStt] as a `pangea.representation` related to the
/// parent audio event. Best-effort: [PangeaEventSender] (`sendPangeaEvent`)
/// already swallows failures and returns null, which this surfaces unchanged --
/// a null/failed return means "not attached" (the message stays eligible for a
/// later repair) and MUST NOT be treated as fatal by callers. The parent event
/// must already exist server-side (call only after `sendFileEvent` resolves).
Future<Event?> attachSttRepresentation({
  required PangeaEventSender send,
  required String parentEventId,
  required SpeechToTextResponseModel richStt,
}) => send(
  content: buildSttRepresentation(richStt).toJson(),
  parentEventId: parentEventId,
  type: PangeaEventTypes.representation,
);

/// DISPLAY-ONLY token repair (never records analytics). Returns [local]
/// unchanged -- and NEVER tokenizes -- when the caller does not [requireTokens]
/// or [local] already has usable tokens; otherwise it [enrich]es (the single
/// tokenize step) and [attach]es best-effort, returning the token-rich result.
///
/// This is the shared repair primitive: the toolbar loader calls it with
/// `requireTokens: true` (tap-to-select needs spans); the text-only translation
/// path leaves the default `false` so it is NOT dragged through the tokenizer
/// despite a usable text embed.
Future<SpeechToTextResponseModel> repairSttTokens({
  required SpeechToTextResponseModel local,
  required bool requireTokens,
  required SttLangSnapshot snapshot,
  required Future<SpeechToTextResponseModel> Function(
    SpeechToTextResponseModel base,
    SttLangSnapshot snapshot,
  )
  enrich,
  required Future<Event?> Function(SpeechToTextResponseModel richStt) attach,
}) async {
  if (!requireTokens || local.hasUsableTokens) return local;
  final rich = await enrich(local, snapshot);
  // Best-effort: a null/failed attach only affects display-repair eligibility.
  await attach(rich);
  return rich;
}
