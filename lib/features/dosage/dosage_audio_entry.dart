import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/dosage/dosage_voice_message.dart';

/// One play, voice message or call as a row in the student's analytics room, so
/// its duration syncs like every other use and survives being offline or killed.
///
/// A row of its own rather than a field on `pvm`, `pvc` or `hrd`: those are per
/// word, and audio with no saved words, such as a call with no transcript, has
/// none. It is one row per audio, never per second.
///
/// Nothing reads it but the server's speaking and listening minutes:
/// `constructType: "g"` is skipped by every app and every figure, and it is worth
/// 0 XP. The empty lemma hides it from local reads until it uploads. It carries
/// no room and no message, like every listening row.
///
/// [OneConstructUse.id] is the POST lane's own key for the same audio, so the
/// server counts the two as one, and a re-sent event once.
class DosageAudioEntry {
  DosageAudioEntry._();

  /// A voice message; the coverage category speaking is declared under.
  static const String voiceCategory = 'voice_send';

  /// A call. Connected time, not speech: a call is not separated by speaker.
  static const String callCategory = 'call_connected';

  /// The server's ceiling on one signal.
  static const int maxDurMs = DosageVoiceMessage.maxDurationMs;

  /// The id a call's POST row is stored under on the server.
  static String callId(String id) => 'call:$id';

  /// The row, or null when there is no real duration to report.
  static OneConstructUse? use({
    required String id,
    required String category,
    required int durMs,
    required DateTime ts,
  }) {
    if (id.isEmpty || durMs <= 0 || durMs > maxDurMs) return null;
    return OneConstructUse(
      useType: ConstructUseTypeEnum.aud,
      lemma: '',
      constructType: ConstructTypeEnum.vocab,
      category: category,
      form: null,
      xp: ConstructUseTypeEnum.aud.pointValue,
      id: id,
      durMs: durMs,
      metadata: ConstructUseMetaData(
        roomId: null,
        eventId: null,
        timeStamp: ts.toUtc(),
      ),
    );
  }
}
