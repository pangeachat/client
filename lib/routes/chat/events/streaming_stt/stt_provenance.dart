import 'dart:math' as math;

import 'package:characters/characters.dart';

import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';

/// Additive `user_stt` provenance keys (Phase-2 D9). Wave 5 WRITES these onto
/// the `user_stt` embed map when a streamed voice transcript is sent; wave 4
/// only defines them + the reader ([sttTranscriptEditedFromUserStt]) and the
/// value ([StreamingSttSendData]) so nothing is lost before the send path is
/// wired. Kept as string literals here (not on the response model) so the
/// orange-flag reader never depends on a full `SpeechToTextResponseModel`
/// parse — a minimal `{edited: true}` embed must still light the flag.
class SttProvenanceKeys {
  SttProvenanceKeys._();

  /// `bool` — true iff the learner edited the ASR transcript before sending.
  static const String edited = 'edited';

  /// `int` — Levenshtein distance between the original ASR text and the sent
  /// text (grapheme-cluster level; see [sttEditDistance]).
  static const String editDistance = 'edit_distance';

  /// `String` — the verbatim settled ASR final captured before any edit.
  static const String originalAsr = 'original_asr';
}

/// Reads the D9 `edited` provenance flag out of a raw `user_stt` embed map.
///
/// Pure + null-tolerant so it is unit-testable without a Matrix event and can
/// never throw on a historical/partial embed: returns `true` ONLY when the map
/// carries `edited == true`. A missing key, a `null` map, or any non-`true`
/// value (including the string `"true"`, which the writer never emits) reads as
/// NOT edited — the flag fails closed to "verbatim".
bool sttTranscriptEditedFromUserStt(Map<String, dynamic>? userStt) =>
    userStt != null && userStt[SttProvenanceKeys.edited] == true;

/// Levenshtein edit distance between [a] and [b] over Unicode grapheme
/// clusters (the same unit [PangeaTextController] counts keystrokes in), so a
/// multi-code-unit character (an emoji, an accented letter written as base +
/// combining mark) counts as ONE edit, not several. Pure; symmetric;
/// identical strings → 0. Two-row DP, O(min·max) time / O(max) space.
int sttEditDistance(String a, String b) {
  if (a == b) return 0;
  final s = a.characters.toList(growable: false);
  final t = b.characters.toList(growable: false);
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  var prev = List<int>.generate(t.length + 1, (i) => i, growable: false);
  var curr = List<int>.filled(t.length + 1, 0);
  for (var i = 1; i <= s.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= t.length; j++) {
      final cost = s[i - 1] == t[j - 1] ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[t.length];
}

/// The provenance-bearing value the recorder hands to the send path (Phase-2
/// D9). Wave 4 COMPUTES and holds this in recorder state; wave 5 consumes it to
/// build the `user_stt` embed (verbatim → carry `word_timings`; edited → OMIT
/// `word_timings` per D8 and write the [SttProvenanceKeys] provenance).
///
/// Immutable snapshot: built once at send from the settled
/// [EditableTranscript]. [editDistance] is `Levenshtein(originalAsrText, text)`;
/// on a verbatim send it is `0` and [isEdited] is `false`.
class StreamingSttSendData {
  const StreamingSttSendData({
    required this.text,
    required this.originalAsrText,
    required this.isEdited,
    required this.editDistance,
    required this.words,
    required this.service,
    required this.langCode,
  });

  /// The user-approved transcript actually sent (verbatim ASR, or the edit).
  final String text;

  /// The verbatim settled ASR final captured before any edit.
  final String originalAsrText;

  /// Whether [text] diverges from [originalAsrText] via a real user edit.
  final bool isEdited;

  /// `Levenshtein(originalAsrText, text)` at grapheme granularity.
  final int editDistance;

  /// The streaming per-word timings — aligned with [originalAsrText] ONLY.
  final List<SttWord> words;

  /// The streaming engine that produced the transcript (e.g. `deepgram`).
  final String service;

  /// The gated language the relay transcribed in (D4 `?lang=` short code),
  /// captured at recording start. The send stamps the streamed `lang_code` +
  /// `speaker_l2` from THIS, never from send-time settings, so a mid-flow L2
  /// change cannot mislabel/mis-tokenize the already-transcribed audio.
  final String langCode;

  /// The additive `user_stt` provenance keys (D9) for wave 5's embed. Always
  /// carries all three keys so a later analytics mirror has the full picture;
  /// the visible orange flag keys off [SttProvenanceKeys.edited] only.
  Map<String, dynamic> toProvenanceKeys() => {
    SttProvenanceKeys.edited: isEdited,
    SttProvenanceKeys.editDistance: editDistance,
    SttProvenanceKeys.originalAsr: originalAsrText,
  };
}

/// Reads the D9 `original_asr` provenance string out of a raw `user_stt` embed
/// map. Pure + null-tolerant: returns the verbatim original ASR only when the
/// key holds a String; null on an absent / malformed / non-String value.
String? sttOriginalAsrFromUserStt(Map<String, dynamic>? userStt) {
  final value = userStt?[SttProvenanceKeys.originalAsr];
  return value is String ? value : null;
}

/// The (original ASR, sent transcript) pair the tappable edited-flag diff (D10)
/// renders. Pure + fails closed to null: a pair is returned ONLY for a
/// learner-edited streamed send (`edited == true`) that carries both a String
/// `original_asr` and a non-empty sent transcript (parsed from the SAME embed's
/// [SpeechToTextResponseModel]). A verbatim / legacy / malformed embed -> null.
typedef SttDiffPair = ({String originalAsr, String current});

SttDiffPair? sttDiffPairFromUserStt(Map<String, dynamic>? userStt) {
  if (!sttTranscriptEditedFromUserStt(userStt)) return null;
  final original = sttOriginalAsrFromUserStt(userStt);
  if (original == null) return null;
  String? current;
  try {
    current = SpeechToTextResponseModel.fromJson(
      Map<String, dynamic>.from(userStt!),
    ).transcript.text;
  } catch (_) {
    current = null;
  }
  if (current == null || current.isEmpty) return null;
  return (originalAsr: original, current: current);
}
