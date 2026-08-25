import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
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
/// The analytics sink saying it stored NOTHING.
///
/// Only this failure is safe to retry. Anything else may have written the
/// uses already, and crediting them twice records the learner as having said
/// everything twice -- their counts, and the proficiency drawn from them,
/// quietly wrong.
class CallAnalyticsNotStored implements Exception {
  final Object cause;

  const CallAnalyticsNotStored(this.cause);

  @override
  String toString() => 'CallAnalyticsNotStored: $cause';
}

/// Publishes this device's transcript half. See `transcript_writer.dart`.
typedef TranscriptPublisher =
    Future<void> Function({
      required String callKey,
      required List<TranscriptSegment> segments,
      required int chunksCaptured,
      required int chunksTranscribed,
      required bool drainComplete,
      String? langCode,
    });

class CallRecord {
  final CallEventSender sendEvent;

  /// Publishes this device's transcript half, if the feature is wired up.
  ///
  /// Optional so every existing construction of a record keeps working
  /// unchanged, and so a deployment can leave transcripts unpublished without
  /// touching this class.
  final TranscriptPublisher? publishTranscript;
  final CallAnalyticsSink analytics;
  final CallTranscriptSink transcripts;
  final String roomId;

  /// The card actually written to the timeline by THIS device, once it has
  /// been. Split from [_anchorId] deliberately: on the side that does not
  /// write, analytics still need an event to credit against, and folding both
  /// meanings into one field made "analytics anchored" read as "the card
  /// exists" -- which blocked the survivor write before it started.
  String? _cardEventId;

  /// What analytics credit against: the card if this device wrote it, the
  /// ring notification it answered with otherwise.
  String? _anchorId;

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
    this.publishTranscript,
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
  /// Puts the call in the timeline, NOW.
  ///
  /// Called the moment the call ends, before teardown and long before the
  /// transcripts exist. Everything a card states — how long, answered, turned
  /// down, video, who called — is known at that instant, and none of it depends
  /// on speech-to-text. Waiting for the transcripts to write it (which is what
  /// this used to do, because crediting and writing were one step at the end of
  /// teardown) put the card 10-60 seconds behind the call and lost it entirely
  /// whenever the learner closed the tab or navigated away in between.
  ///
  /// Idempotent, and the id it establishes is what [finish] later credits
  /// against, so the two can never produce two cards.
  Future<void> writeCard({
    required Duration duration,
    required bool video,
    required bool answered,
    required bool declined,
    required bool writeTimelineEvent,
    String? anchorEventId,
    String? callerId,
    String? callKey,
  }) async {
    if (_anchorId != null || _cardEventId != null || _credited) return;
    if (!writeTimelineEvent) {
      // The answering side posts no card; its analytics anchor to the ring it
      // was called with, which it already holds. The card slot stays empty --
      // that emptiness is what lets the survivor path act later.
      _anchorId = anchorEventId;
      return;
    }
    for (var attempt = 0; attempt < 3 && _cardEventId == null; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(seconds: attempt));
      try {
        _cardEventId = await _write(
          duration: duration,
          video: video,
          answered: answered,
          declined: declined,
          callerId: callerId,
          callKey: callKey,
        );
      } catch (e, s) {
        Logs().w(
          'Writing the call to the timeline failed '
          '(attempt ${attempt + 1})',
          e,
          s,
        );
      }
    }
    if (_cardEventId == null) {
      Logs().e('Gave up putting the call in the timeline');
    } else {
      _anchorId ??= _cardEventId;
    }
  }

  /// Writes the card a dead writer never did.
  ///
  /// Run by the surviving NON-writer after the settle window, only when no
  /// card carrying this call's key has appeared. Deliberately indifferent to
  /// [_credited]: analytics were anchored to the ring long before, and having
  /// been credited is not the same fact as the card existing. Its own txid --
  /// Matrix transaction ids dedup PER DEVICE, so reusing the writer's could
  /// never collapse against it anyway; the renderer's first-per-key rule is
  /// what makes the rare double-write invisible.
  Future<void> writeSurvivorCard({
    required Duration duration,
    required bool video,
    required String callKey,
    required bool answered,
    required bool declined,
    String? callerId,
  }) async {
    if (_cardEventId != null) return;
    for (var attempt = 0; attempt < 3 && _cardEventId == null; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(seconds: attempt));
      try {
        _cardEventId = await _write(
          duration: duration,
          video: video,
          // The outcome this side actually saw, never an assumption. Hard-
          // coding "answered" here read every recovered call as a
          // conversation, including the ones where nobody ever arrived: a
          // caller whose app dies mid-ring leaves a membership that makes a
          // call BACK look like glare, and the survivor then wrote "Voice
          // call" for a call that never connected.
          answered: answered,
          declined: declined,
          callerId: callerId,
          callKey: callKey,
        );
      } catch (e, s) {
        Logs().w(
          'The survivor card write failed (attempt ${attempt + 1})',
          e,
          s,
        );
      }
    }
  }

  Future<void> finish({
    required Duration duration,
    required bool video,
    bool answered = true,
    bool declined = false,
    bool writeTimelineEvent = true,
    String? anchorEventId,
    String? callerId,
    String? callKey,
  }) async {
    // Ahead of every guard below, because none of them are about the
    // transcript. Publishing lives outside the credit's control flow entirely:
    // it needs only the anchor, and it is a separate promise to the learner.
    //
    // Both couplings were real. Inside _finish it sat after the card's event id
    // was resolved, so a card that failed to write ALSO cost the transcript --
    // though publishing never needed the card. And behind the _credited check
    // it was unreachable whenever an earlier finish had credited without a
    // call key, which is exactly the sequence the ordinary lifecycle produces.
    await _publishTranscript(callKey);

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
              callKey: callKey,
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
    required String? callKey,
  }) async {
    // Written once. A retry after the analytics failed must credit against the
    // call already in the timeline, not add another one.
    final eventId = _anchorId ??= writeTimelineEvent
        ? (_cardEventId ??= await _write(
            duration: duration,
            video: video,
            answered: answered,
            declined: declined,
            callerId: callerId,
            callKey: callKey,
          ))
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

    // Marked BEFORE the await, because crediting is not something that can be
    // safely done twice. The analytics service writes the uses locally as its
    // first act and only then does the work that can fail, so a second call
    // after a failure does not retry the credit — it adds it again, and the
    // learner is recorded as having said everything twice. Their counts and the
    // proficiency drawn from them would be quietly wrong.
    //
    // What is lost by not retrying is only the part that already succeeded
    // locally: sending it on to the analytics room is the analytics service's
    // own job, on its own schedule, and it retries that itself. The ordinary
    // lifecycle calls this twice, so without this the SECOND call was a
    // duplicate rather than a retry.
    _credited = true;
    try {
      await analytics(eventId, uses, language!);
    } on CallAnalyticsNotStored catch (e, s) {
      // Nothing was written, so there is nothing to double. Putting the flag
      // back is the only way this learner's speech gets another chance: the
      // ordinary lifecycle calls this again, and without it that second call
      // returned immediately and the words were gone.
      _credited = false;
      Logs().w('The call\'s speech was not credited; it can be retried', e, s);
    }
  }

  /// Publishes this device's half of the conversation, at most once.
  ///
  /// Separate from the analytics credit on purpose: a learner's XP and the
  /// readable record of what they said are different promises, and one failing
  /// must not cost the other. A transcript that does not publish is a gap in
  /// the history; a credit applied twice is a learner's proficiency quietly
  /// wrong, which is why only the latter is guarded by [_credited].
  Future<void> _publishTranscript(String? callKey) async {
    final publish = publishTranscript;
    if (publish == null || _published || callKey == null) return;

    // Marked before the await, and NOT reset on failure. The retry loop above
    // exists for the credit, and re-entering here on a later attempt would
    // publish a second half for the same call under a different transaction id
    // if the first had in fact landed. One attempt per call is the safe side of
    // that trade: a missing transcript is visible and recoverable, a duplicated
    // one is speech the learner never said twice.
    _published = true;
    try {
      await publish(
        callKey: callKey,
        segments: transcripts.segments,
        chunksCaptured: transcripts.chunksCaptured,
        chunksTranscribed: transcripts.chunksTranscribed,
        // Meaningful only once the sink has closed, which the capture service
        // does before this runs. Read earlier it would be the optimistic
        // default and a half could claim a completeness nothing had checked.
        drainComplete: transcripts.drainComplete,
        langCode: transcripts.langCode,
      );
    } catch (e, s) {
      // Swallowed rather than rethrown, so a transcript failure cannot drag the
      // credit into the retry loop above. Belt and braces as things stand --
      // the loop would retry and the guard above would skip the second publish,
      // reaching the same outcome -- and deliberately NOT covered by a test,
      // because no observable behaviour distinguishes it today. It earns its
      // place the moment that retry loop changes, which is exactly when nobody
      // will be thinking about this.
      Logs().w('The call transcript was not published', e, s);
    }
  }

  bool _published = false;

  /// How long a call in the timeline lasted, read from its content.
  ///
  /// Defensive because this event is written by other clients and by older
  /// versions of this one: a cast that throws while drawing the timeline takes
  /// down the whole row rather than one number in it.
  static Duration durationOf(Map<String, Object?> content) {
    final ms = content['duration_ms'];
    if (ms is num) return Duration(milliseconds: ms.round());
    if (ms is String) {
      final parsed = num.tryParse(ms);
      if (parsed != null) return Duration(milliseconds: parsed.round());
    }
    return Duration.zero;
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

  /// The one field the renderer's first-per-key rule reads, and the one every
  /// writer of a card stamps. Kept as a constant so no path can misspell it.
  static const callKeyField = 'call_key';

  Future<String?> _write({
    required Duration duration,
    required bool video,
    required bool answered,
    required bool declined,
    required String? callerId,
    required String? callKey,
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
        // The call's SHARED identity: the caller's membership event id, known
        // to both sides (the caller as its own echo, the callee from its
        // ring). It is what lets two devices' cards for one call be told
        // apart from two calls -- the renderer draws only the first card per
        // key. Absent on calls whose identity was never learned; those render
        // unconditionally, as they always did.
        callKeyField: ?callKey,
      }, _txid);
    } catch (e, s) {
      Logs().e('Could not write the call to the room', e, s);
      return null;
    }
  }
}
