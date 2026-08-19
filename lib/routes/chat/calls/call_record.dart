import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Writes the call to the room and returns the event id, or null if it could
/// not be written.
typedef CallEventSender =
    Future<String?> Function(Map<String, dynamic> content, String txid);

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

  /// The call's timeline event, once written. Kept so a retry credits against
  /// the same event rather than posting a second call.
  String? _eventId;

  /// One transaction id for every attempt at writing this call.
  ///
  /// A send whose response is lost may already have been persisted, and a retry
  /// with a fresh id would post the call a second time. Reusing this makes the
  /// homeserver return the event the first attempt actually created.
  late final String _txid =
      'pangea.call.${DateTime.now().microsecondsSinceEpoch}.$roomId';

  /// Whether the learner has actually been credited. Separate from the event
  /// being written, because the two fail independently and only one of them
  /// being done is not done.
  bool _credited = false;
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
  /// [writeTimelineEvent] is false on the device that ANSWERED the call. Both
  /// sides run the same lifecycle and both have speech to credit, but only one
  /// card belongs in the conversation — so the answering side anchors its
  /// analytics to [anchorEventId], the notification it was rung with, instead
  /// of posting a second identical call.
  Future<void> finish({
    required Duration duration,
    required bool video,
    bool answered = true,
    bool declined = false,
    bool writeTimelineEvent = true,
    String? anchorEventId,
    String? callerId,
  }) async {
    if (_credited) return;
    // Concurrent callers join the in-flight attempt rather than being dropped.
    // Dropping one made a failed write unretryable in practice: the two callers
    // are the same hangup, and the discarded one was the only other chance.
    return _inFlight ??= () async {
      try {
        // Both callers are the same hangup, and the screen is gone afterwards —
        // there is no later attempt. A transient failure at hangup would
        // otherwise cost the whole call's credit, so the retry lives here.
        for (var attempt = 0; attempt < 3 && !_credited; attempt++) {
          if (attempt > 0) {
            await Future.delayed(Duration(seconds: attempt));
          }
          try {
            await _finish(
              duration: duration,
              video: video,
              answered: answered,
              declined: declined,
              writeTimelineEvent: writeTimelineEvent,
              anchorEventId: anchorEventId,
              callerId: callerId,
            );
          } catch (e, s) {
            // Caught here rather than around each step, so a failure is visible
            // to the loop and can be retried — and so nothing escapes into the
            // hangup path, which does not await this.
            Logs().w(
              'Recording the call failed (attempt ${attempt + 1})',
              e,
              s,
            );
          }
        }
        if (!_credited) {
          Logs().e('Gave up recording this call; its analytics are lost');
        }
      } finally {
        _inFlight = null;
      }
    }();
  }

  Future<void> _finish({
    required Duration duration,
    required bool video,
    required bool answered,
    required bool declined,
    required bool writeTimelineEvent,
    required String? anchorEventId,
    required String? callerId,
  }) async {
    // Written once. A retry after the analytics failed must credit against the
    // call already in the timeline, not add another one.
    final eventId = _eventId ??= writeTimelineEvent
        ? await _write(
            duration: duration,
            video: video,
            answered: answered,
            declined: declined,
            callerId: callerId,
          )
        : anchorEventId;
    if (eventId == null) {
      // Nothing to anchor the uses to, and an unanchored use cannot be traced
      // back to the call that earned it. Deliberately NOT marked finished: the
      // transcripts are frozen and still correct, so a later attempt — a retry,
      // or a second teardown path — can still record them. A network blip at
      // hangup must not cost the whole call's credit.
      Logs().w('Call analytics not recorded: the call event was not written');
      return;
    }

    if (!answered) {
      // Nothing was said to anyone. The call is in the timeline so it is not
      // lost, but there is no conversation to credit.
      _credited = true;
      return;
    }

    final language = transcripts.langCode;
    final uses = language == null
        ? const <OneConstructUse>[]
        : transcripts.constructs(roomId: roomId, eventId: eventId);

    if (uses.isEmpty) {
      // Nothing was said that speech-to-text could read. The call is in the
      // timeline and there is genuinely nothing to credit, so this is done
      // rather than pending.
      _credited = true;
      return;
    }

    // Marked only on success. Recording the whole thing as done when the event
    // was written but the credit was not would lose the learner's analytics
    // permanently — and the ordinary lifecycle calls this twice, so the second
    // call is the retry.
    await analytics(eventId, uses, language!);
    _credited = true;
  }

  /// What a client that cannot draw a call card shows instead.
  ///
  /// Deliberately not translated: this is the interop fallback stored in the
  /// event, read by other clients and by search, while the card this app draws
  /// is localised at render time. A stored translation would be the sender's
  /// language, not the reader's.
  static String _fallbackText({
    required Duration duration,
    required bool video,
    required bool answered,
    required bool declined,
  }) {
    if (declined) return 'Call declined';
    if (!answered) return video ? 'Missed video call' : 'Missed call';
    final seconds = duration.inSeconds;
    final stamp =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return video ? 'Video call ($stamp)' : 'Voice call ($stamp)';
  }

  Future<String?> _write({
    required Duration duration,
    required bool video,
    required bool answered,
    required bool declined,
    required String? callerId,
  }) async {
    try {
      return await sendEvent(<String, dynamic>{
        'msgtype': PangeaEventTypes.call,
        // The plaintext fallback every Matrix client falls back to when it does
        // not understand the msgtype. Without it a call reads as an empty
        // message everywhere but here.
        'body': _fallbackText(
          duration: duration,
          video: video,
          answered: answered,
          declined: declined,
        ),
        'duration_ms': duration.inMilliseconds,
        'video': video,
        // A call nobody answered still belongs in the conversation. Every
        // calling product shows a missed call, and a learner who was away
        // would otherwise have no idea anyone had tried to reach them.
        'answered': answered,
        // Turned down, as opposed to simply not picked up. Every calling product
        // draws that line, and a learner reading their history should see the
        // difference between being declined and being missed.
        'declined': declined,
        // Who placed the call, stated rather than inferred from who wrote the
        // event. Which side writes is decided deterministically so that exactly
        // one card exists even when both people call at the same moment, and
        // that side is not always the caller.
        //
        // The `?` before the value is a null-aware entry: the key is left out
        // entirely when there is nobody to name. It reads like a mistake and is
        // not — the analyser suggests this form, and it has been reported as a
        // compile error twice by review.
        'caller': ?callerId,
      }, _txid);
    } catch (e, s) {
      Logs().e('Could not write the call to the room', e, s);
      return null;
    }
  }
}
