import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Writes the call to the room and returns the event id, or null if it could
/// not be written.
typedef CallEventSender =
    Future<String?> Function(Map<String, dynamic> content);

/// Records construct uses. The real caller passes the analytics service's
/// `addAnalytics`, already bound to a service resolved while the screen was live.
typedef CallAnalyticsSink =
    Future<void> Function(
      String eventId,
      List<OneConstructUse> constructs,
      String langCode,
    );

/// Turns a finished call into a timeline entry and speaking analytics.
///
/// Deliberately free of any widget or context: it is created while the call
/// screen is live but it runs after the call ends, and the user hanging up is
/// exactly the moment that screen goes away. A recorder that needed the screen
/// would lose the analytics of every call that ended normally.
class CallRecord {
  final CallEventSender sendEvent;
  final CallAnalyticsSink analytics;
  final CallTranscriptSink transcripts;
  final String roomId;

  bool _finished = false;
  Future<void>? _inFlight;

  CallRecord({
    required this.sendEvent,
    required this.analytics,
    required this.transcripts,
    required this.roomId,
  });

  /// Writes the call and records what was said.
  ///
  /// The timeline entry is written even when nothing was transcribed: the call
  /// happened, and a learner looking back should see it whether or not it earned
  /// them anything.
  ///
  /// Idempotent. Running twice would post a second timeline entry and credit the
  /// same words again, and a hangup racing a disconnect can reach here twice.
  Future<void> finish({required Duration duration, required bool video}) async {
    if (_finished) return;
    // Concurrent callers join the in-flight attempt rather than being dropped.
    // Dropping one made a failed write unretryable in practice: the two callers
    // are the same hangup, and the discarded one was the only other chance.
    return _inFlight ??= () async {
      try {
        await _finish(duration: duration, video: video);
      } finally {
        _inFlight = null;
      }
    }();
  }

  Future<void> _finish({
    required Duration duration,
    required bool video,
  }) async {
    final eventId = await _write(duration: duration, video: video);
    if (eventId == null) {
      // Nothing to anchor the uses to, and an unanchored use cannot be traced
      // back to the call that earned it. Deliberately NOT marked finished: the
      // transcripts are frozen and still correct, so a later attempt — a retry,
      // or a second teardown path — can still record them. A network blip at
      // hangup must not cost the whole call's credit.
      Logs().w('Call analytics not recorded: the call event was not written');
      return;
    }
    _finished = true;

    final language = transcripts.langCode;
    if (language == null) return;

    final uses = transcripts.constructs(roomId: roomId, eventId: eventId);
    if (uses.isEmpty) return;

    try {
      await analytics(eventId, uses, language);
    } catch (e, s) {
      Logs().e('Could not record call analytics', e, s);
    }
  }

  Future<String?> _write({
    required Duration duration,
    required bool video,
  }) async {
    try {
      return await sendEvent({
        'msgtype': PangeaEventTypes.call,
        'body': '',
        'duration_ms': duration.inMilliseconds,
        'video': video,
      });
    } catch (e, s) {
      Logs().e('Could not write the call to the room', e, s);
      return null;
    }
  }
}
