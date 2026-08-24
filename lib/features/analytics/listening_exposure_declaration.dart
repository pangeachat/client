import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';

/// What a read-aloud call is about to say, as constructs.
///
/// The listening lane already makes each caller name its category, because the
/// shared `TtsController.tryToSpeak` entry point is handed neither a room nor
/// an event and cannot derive one. The lemmas are the same kind of fact and
/// arrive the same way: only the caller knows which tokens its utterance
/// covers, so only the caller can declare them.
///
/// **Declaring is required, and [exempt] is how a path opts out.** Optional
/// instrumentation makes forgetting it the default — a new read-aloud path
/// would compile, analyze clean, pass every behavioural test and silently
/// record no exposure. A required parameter turns that omission into a compile
/// error, and a named exemption turns "this path speaks no L2 lemma" into
/// something a reader can check rather than infer from an absence.
///
/// See message-read-aloud.instructions.md (Word-level exposure).
class ListeningExposureDeclaration {
  /// The constructs this utterance covers.
  const ListeningExposureDeclaration(this.constructs) : exemptReason = null;

  /// This path speaks nothing that should count as exposure to a lemma.
  ///
  /// [reason] is not read at runtime; it exists so the next reader can tell a
  /// deliberate exemption from an oversight.
  const ListeningExposureDeclaration.exempt(String reason)
    : constructs = const <ConstructIdentifier>[],
      exemptReason = reason;

  /// The vocab constructs of [tokens] that are worth saving.
  ///
  /// `saveVocab` is the same gate every other lemma-level signal applies, so a
  /// token the rest of analytics ignores does not become visible only because
  /// it was read aloud.
  factory ListeningExposureDeclaration.ofTokens(Iterable<PangeaToken> tokens) =>
      ListeningExposureDeclaration([
        for (final token in tokens)
          if (token.lemma.saveVocab) token.vocabConstructID,
      ]);

  final List<ConstructIdentifier> constructs;
  final String? exemptReason;

  /// Records one exposure per declared construct against [userId]'s buffer.
  ///
  /// Synchronous and allocation-only: this runs on the playback path. Called
  /// only when a route actually played, so an utterance that resolved having
  /// spoken nothing records nothing.
  void record(String? userId) {
    if (constructs.isEmpty) return;
    ListeningExposureBuffer.forAccount(userId ?? "")?.record(constructs);
  }
}
