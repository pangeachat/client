import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_signal_identity.dart';
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

  /// Records one finished playback against [category].
  ///
  /// [roomId] is required and is the ONLY identifier that travels: no source
  /// event id and no source sender, even though categories 1 and 3 have both in
  /// hand at this moment. See [DosageAudioEvent].
  ///
  /// Synchronous and allocation-only — it appends to an in-memory buffer and
  /// returns. Nothing is awaited, nothing is posted, and no user action waits on
  /// it. Delivery happens on the analytics heartbeat.
  static void recordPlayback({
    required DosageListeningCategory category,
    required String roomId,
    required Duration elapsed,
    required String? userId,
    required String? accessToken,
    DateTime? endedAt,
    DosageAudioBuffer? buffer,
  }) {
    try {
      if (roomId.isEmpty) return;
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
