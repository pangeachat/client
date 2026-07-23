import 'dart:async';

import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/analytics/constructs_model.dart';
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
  // Defensive no-op: an exhausted-fallback / non-usable response has no
  // transcript to tokenize, so there is nothing to enrich. Return it unchanged
  // rather than tokenizing empty text or dereferencing a missing transcript.
  if (!baseStt.hasUsableTranscript) return baseStt;

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

/// Invokes [report] and CONTAINS both failure modes so a failing logger can
/// never escape as an unhandled error: a SYNCHRONOUS throw is caught, and an
/// ASYNC rejection (production's `onError` is `(e,s) => ErrorHandler.logError`,
/// which returns a `Future<void>`) is swallowed via `catchError`. Used at EVERY
/// error-callback site (the coordinator's `safeOnError`, the flag-OFF feedback
/// dispatch), so a throwing/rejecting logger cannot reject the fire-and-forget.
void reportErrorSafely(
  FutureOr<void> Function(Object error, StackTrace stack)? report,
  Object error,
  StackTrace stack,
) {
  try {
    final result = report?.call(error, stack);
    if (result is Future) {
      unawaited(result.catchError((Object _) {}));
    }
  } catch (_) {
    // The logger itself threw synchronously; there is nowhere safe left to
    // report it, and it must not reject the caller.
  }
}

/// Whether an audio event was sent by the local user -- the analytics-record
/// gate (D7): recording fires only for the sender's OWN message, never for a
/// viewed other-sender or bot message. Bound to the real identity path
/// ([senderId] from the event, [clientUserId] from the Matrix client), never a
/// hardcoded bool, so if the record primitive is ever reached for a foreign
/// sender it correctly does NOT record.
bool isOwnSender(String? senderId, String? clientUserId) =>
    senderId != null && clientUserId != null && senderId == clientUserId;

/// The analytics record call, injectable so the recorder can be driven without
/// a live `AnalyticsUpdateService`. The real caller passes
/// `analyticsService.addAnalytics`.
typedef VoiceAnalyticsSink =
    Future<void> Function(
      String eventId,
      List<OneConstructUse> constructs,
      String langCode,
    );

/// Builds the LIFECYCLE-INDEPENDENT voice-analytics recorder. It CAPTURES
/// [sink] (the analytics service's `addAnalytics`, already bound to a service
/// resolved while the widget was live) plus [roomId]/[eventId] as plain values,
/// so the returned closure records regardless of whether the originating widget
/// is later disposed -- it never reads a `BuildContext`. It records ONLY (the
/// visual feedback is a separate best-effort `showFeedback` the coordinator
/// owns and guards, so a feedback failure can never abort the record).
Future<void> Function(SpeechToTextResponseModel richStt)
buildVoiceAnalyticsRecorder({
  required String roomId,
  required String eventId,
  required VoiceAnalyticsSink sink,
}) {
  return (SpeechToTextResponseModel richStt) async {
    if (!richStt.hasUsableTranscript || richStt.transcript.sttTokens.isEmpty) {
      return;
    }
    final constructs = richStt.constructs(roomId, eventId);
    if (constructs.isEmpty) return;
    final langCode = richStt.langCode.split('-').first;
    await sink(eventId, constructs, langCode);
  };
}

/// The background half of a decoupled voice send, run fire-and-forget AFTER
/// `sendFileEvent` resolves (so the caller returns and the bot replies without
/// waiting for the tokenizer).
///
/// This owns ALL the orchestration + error-wrapping so the caller stays thin
/// wiring: the real-event sender lookup ([resolveSenderId]), the record, the
/// visual feedback dispatch, and the attach are each guarded here so NOTHING
/// escapes the fire-and-forget. Every dependency is injected and this never
/// touches a widget `BuildContext`, so it is LIFECYCLE-INDEPENDENT -- navigating
/// away before [enrich] resolves still records analytics.
///
/// Ordering (PHASE1-SPEC D7):
///  0. If [baseStt] has no usable transcript (exhausted-fallback): no-op.
///  1. [resolveSenderId] -- the sent event's real sender, looked up here inside
///     a catch: a DB/network/decryption throw routes to [onError] and leaves
///     senderId null (-> not own -> no record), never escaping.
///  2. [enrich] -- the single tokenize step. On failure nothing else runs.
///  3. [recordAnalytics] fires ONCE, only when [isOwnSender]([senderId],
///     [clientUserId]), gated on ENRICH success -- NOT attach.
///  4. [showFeedback] (optional) -- best-effort visual, own catch, NEVER
///     affects the record above and never escapes.
///  5. [attach] best-effort; a null/failed return only affects later display
///     repair, never analytics.
Future<void> runVoiceTranscriptEnrichment({
  required SpeechToTextResponseModel baseStt,
  required SttLangSnapshot snapshot,
  required Future<String?> Function() resolveSenderId,
  required String? clientUserId,
  required Future<SpeechToTextResponseModel> Function(
    SpeechToTextResponseModel base,
    SttLangSnapshot snapshot,
  )
  enrich,
  required Future<void> Function(SpeechToTextResponseModel richStt)
  recordAnalytics,
  required Future<Event?> Function(SpeechToTextResponseModel richStt) attach,
  Future<void> Function(SpeechToTextResponseModel richStt)? showFeedback,
  FutureOr<void> Function(Object error, StackTrace stack)? onError,
}) async {
  // A logger must NEVER reject this fire-and-forget coordinator: contain BOTH a
  // synchronous throw AND an async rejection of the logger's returned Future.
  void safeOnError(Object e, StackTrace s) => reportErrorSafely(onError, e, s);

  // Nothing to tokenize on an exhausted-fallback/non-usable transcript: skip
  // all background work rather than crashing on the missing transcript.
  if (!baseStt.hasUsableTranscript) return;

  // Real-event sender lookup, owned + guarded here: a throw must not escape the
  // fire-and-forget. On failure senderId stays null -> not own -> no record.
  String? senderId;
  try {
    senderId = await resolveSenderId();
  } catch (e, s) {
    safeOnError(e, s);
  }

  final SpeechToTextResponseModel richStt;
  try {
    richStt = await enrich(baseStt, snapshot);
  } catch (e, s) {
    safeOnError(e, s);
    return;
  }

  if (isOwnSender(senderId, clientUserId)) {
    try {
      await recordAnalytics(richStt);
    } catch (e, s) {
      safeOnError(e, s);
    }
    // Feedback is best-effort and INDEPENDENT of the record above: its own
    // catch swallows+logs any overlay/count failure so it never affects the
    // record and never escapes the fire-and-forget.
    if (showFeedback != null) {
      try {
        await showFeedback(richStt);
      } catch (e, s) {
        safeOnError(e, s);
      }
    }
  }

  try {
    await attach(richStt);
  } catch (e, s) {
    safeOnError(e, s);
  }
}
