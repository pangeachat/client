import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_signal_identity.dart';
import 'package:fluffychat/features/dosage/dosage_voice_message.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// The single place a finished playback becomes a dosage signal.
///
/// Every listening call site funnels through here so the minimisation rule, the
/// identity plumbing and the best-effort boundary live in one place rather than
/// copy-pasted three times. What each call site supplies is the one thing only
/// it knows: **which category of listening this was**.
///
/// Fire-and-forget and never throws. The whole body is guarded and swallowed, so
/// a failure in telemetry can never surface in playback — the learner must not
/// be able to tell whether this feature exists.
class DosageAudioSignals {
  DosageAudioSignals._();

  /// Opens an unconfirmed voice-send envelope on [userId]'s buffer and returns
  /// the callback that settles it.
  ///
  /// Speaking's magnitude is derived server-side from the `m.audio` event, but
  /// its DENOMINATOR is not: the server learns a voice message exists only from
  /// a client-originated row. So `voice_send` coverage — the declaration that
  /// licenses the server to serve a speaking zero — may only be made for a
  /// period whose envelopes actually landed. This is what connects the two.
  ///
  /// Returns a no-op callback for an unknown account, so the call site is
  /// unconditional. Never throws.
  static void Function(bool delivered) voiceSendReporter({
    required String? userId,
  }) {
    DosageAudioBuffer? buffer;
    try {
      buffer = DosageAudioBuffer.forAccount(userId ?? "");
      buffer?.noteVoiceSendPending();
    } catch (_) {
      buffer = null;
    }
    var settled = false;
    return (delivered) {
      if (settled) return;
      settled = true;
      try {
        buffer?.noteVoiceSendSettled(delivered: delivered);
      } catch (_) {}
    };
  }

  /// Records a sent voice message and its measured duration, so speaking can
  /// populate for the DM / 1:1 / bot rooms the server's teacher-token path can
  /// never read (admin-dash-api#150 / #104).
  ///
  /// [msgId] MUST be the resolved `m.audio` Matrix event id — the SAME id the
  /// message's envelope and `pvm` uses carry — so the server dedups a retry on
  /// `(sender, msg_id)` and correlates the duration to the right message.
  /// [durationMs] is `content.info.duration`. Both are validated here and again
  /// on the model, and an out-of-range duration or blank id is dropped rather
  /// than sent — a bad row would 422 the whole audio-signals batch server-side.
  ///
  /// Synchronous and allocation-only: it appends to the in-memory buffer and
  /// returns. Nothing is awaited, nothing is posted, and no user action waits on
  /// it. Delivery rides the analytics heartbeat, and the buffer no-ops unless the
  /// capability flag is on, so this stays inert until every server ships #150.
  /// Never throws.
  static void recordVoiceMessage({
    required String? msgId,
    required String? roomId,
    required int durationMs,
    required String? userId,
    required String? accessToken,
    DateTime? sentAt,
    DosageAudioBuffer? buffer,
  }) {
    try {
      if (msgId == null || msgId.trim().isEmpty) return;
      if (roomId == null || roomId.isEmpty) return;
      if (durationMs < 0 || durationMs > DosageVoiceMessage.maxDurationMs) {
        return;
      }
      // An unknown account has no buffer to attribute this to; dropping it is
      // right for the same reason a playback is dropped there.
      final target = buffer ?? DosageAudioBuffer.forAccount(userId ?? "");
      if (target == null) return;
      target.recordVoiceMessage(
        DosageVoiceMessage(
          msgId: msgId,
          roomId: roomId,
          durationMs: durationMs,
          ts: (sentAt ?? DateTime.now()).toUtc(),
        ),
        accessToken: accessToken,
      );
    } catch (e, s) {
      // Best-effort, exactly like [recordPlayback]: the error report is async, so
      // detach it lest a Sentry failure surface on the send path as an unhandled
      // rejection.
      unawaited(
        ErrorHandler.logError(
          e: e,
          s: s,
          level: SentryLevel.warning,
          m: "Best-effort dosage voice-message emit failed (swallowed)",
          data: const {"signal": "voice-message"},
        ).catchError((_) {}),
      );
    }
  }

  /// Records one finished playback against [category].
  ///
  /// [roomId] is the ONLY identifier that travels: no source event id and no
  /// source sender, even though categories 1 and 3 have both in hand at this
  /// moment. See [DosageAudioEvent].
  ///
  /// It is required but NULLABLE, and the two are the point. Null says this
  /// surface has no room, which six of the ten read-aloud sites truthfully
  /// report; required is what stops a site from omitting it and getting that
  /// answer by accident. The empty string is neither and is dropped here — see
  /// [DosageAudioEvent.hasWellFormedRoom].
  ///
  /// Synchronous and allocation-only — it appends to an in-memory buffer and
  /// returns. Nothing is awaited, nothing is posted, and no user action waits on
  /// it. Delivery happens on the analytics heartbeat.
  static void recordPlayback({
    required DosageListeningCategory category,
    required String? roomId,
    required Duration elapsed,
    required String? userId,
    required String? accessToken,
    DateTime? endedAt,
    DosageAudioBuffer? buffer,
  }) {
    try {
      if (roomId != null && roomId.isEmpty) return;
      if (elapsed <= Duration.zero) return;
      // An unknown account has no buffer to attribute this to. Dropping it is
      // right: attributing a playback to the wrong account is worse than losing
      // it, and coverage makes the loss visible as a withheld period rather than
      // a short total.
      final target = buffer ?? DosageAudioBuffer.forAccount(userId ?? "");
      if (target == null) return;
      target.record(
        DosageAudioEvent.fromPlayback(
          playbackId: DosageSignalIdentity.uuidV4(),
          roomId: roomId,
          category: category,
          elapsed: elapsed,
          endedAt: endedAt ?? DateTime.now(),
        ),
        accessToken: accessToken,
      );
    } catch (e, s) {
      // Even the error report is best-effort: ErrorHandler.logError is async, so
      // a Sentry failure surfaces as a REJECTED future that a synchronous
      // try/catch cannot observe. Detach it so it can never reach the playback
      // path as an unhandled error.
      unawaited(
        ErrorHandler.logError(
          e: e,
          s: s,
          level: SentryLevel.warning,
          m: "Best-effort dosage audio emit failed (swallowed)",
          data: {"category": category.wireName},
        ).catchError((_) {}),
      );
    }
  }
}
