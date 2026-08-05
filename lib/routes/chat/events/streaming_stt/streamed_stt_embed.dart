import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';

/// Builds the `user_stt` payload for a STREAMED voice send (Phase-2 D8/D9), so
/// the streaming path reuses the exact Phase-1 tokenizer-decouple machinery: the
/// send embeds a text-usable transcript with `stt_tokens: []`, the bot replies
/// from the embedded text immediately, and the tokens are computed + attached in
/// the background afterwards.
///
/// The model carries the SENT text — the learner's edit if they edited, else the
/// verbatim ASR final — so the bot and every other client read what the learner
/// approved, never the raw ASR. Word timings are CARRIED on a verbatim send
/// (they align with the sent text) and OMITTED on an edited send (they align
/// with the original ASR, not the edited text — D8).
///
/// [streamedUserSttEmbed] wraps this with the D9 provenance keys
/// ([StreamingSttSendData.toProvenanceKeys]) merged at the top level, where the
/// orange-flag reader ([sttTranscriptEditedFromUserStt]) looks.

/// The [SpeechToTextResponseModel] for a streamed send. Usable
/// (`hasUsableTranscript == true`) so the decoupled background tokenize runs on
/// the sent text exactly as it does for a batch transcript.
SpeechToTextResponseModel streamedSttResponse(
  StreamingSttSendData data, {
  required String langCode,
}) {
  // Word timings only make sense when the sent text IS the ASR text. An edit
  // shifts character offsets, so the original timings no longer align — omit
  // them rather than embed a misaligned mapping (D8).
  final List<WordTiming>? wordTimings = data.isEdited || data.words.isEmpty
      ? null
      : data.words
            .map(
              (w) => WordTiming(
                word: w.word,
                startTimeMs: (w.start * 1000).round(),
                endTimeMs: (w.end * 1000).round(),
                confidence: _confidence0to100(w.confidence),
              ),
            )
            .toList(growable: false);

  final transcript = Transcript(
    text: data.text,
    // The learner reviewed (and possibly corrected) the transcript before
    // sending, so it is high-confidence by human approval when the ASR gives no
    // per-word signal; otherwise average the streamed word confidences.
    confidence: data.words.isEmpty
        ? 100
        : _confidence0to100(
            data.words.map((w) => w.confidence).reduce((a, b) => a + b) /
                data.words.length,
          ),
    sttTokens: const [], // skip_tokenize base — background tokenize fills these
    langCode: langCode,
    wordsPerHr: null,
    wordTimings: wordTimings,
  );

  return SpeechToTextResponseModel(
    results: [
      SpeechToTextResult(transcripts: [transcript]),
    ],
    service: data.service,
  );
}

/// The `user_stt` embed map for a streamed send, from an ALREADY-built [model]
/// (so `onVoiceMessageSend` reuses the one model it also feeds to the background
/// tokenize snapshot, without re-synthesizing it). The base STT shape plus the
/// D9 provenance keys merged at the top level — no key collision (base keys are
/// `results`/`service`; provenance keys are `edited`/`edit_distance`/
/// `original_asr`). This is the exact expression production writes to the event,
/// so a test on it pins the real embed.
Map<String, dynamic> userSttEmbedFromModel(
  SpeechToTextResponseModel model,
  StreamingSttSendData data,
) => {...model.toJson(), ...data.toProvenanceKeys()};

/// The `user_stt` embed map written to the Matrix event for a streamed send:
/// [streamedSttResponse] wrapped by [userSttEmbedFromModel].
Map<String, dynamic> streamedUserSttEmbed(
  StreamingSttSendData data, {
  required String langCode,
}) =>
    userSttEmbedFromModel(streamedSttResponse(data, langCode: langCode), data);

/// Whether a voice send drives the decoupled background-tokenize half. A
/// streamed send ALWAYS does (it embeds `stt_tokens: []` by construction, so the
/// tokens must be computed and attached after send); a batch send does so only
/// when the Phase-1 decouple flag is on. `onVoiceMessageSend` calls this at t0
/// (before any await) to gate the analytics sink + snapshot + enrichment, so the
/// "streamed always enriches" rule is one tested predicate, not an inline OR.
bool voiceSendIsDecoupled({
  required bool decoupleFlag,
  required bool isStreamedSend,
}) => decoupleFlag || isStreamedSend;

/// A streamed word confidence (0..1) as the frozen `WordTiming`/`Transcript`
/// contract's integer 0..100 (a valid `0` is preserved, out-of-range clamped).
int _confidence0to100(double confidence) =>
    (confidence * 100).round().clamp(0, 100);
