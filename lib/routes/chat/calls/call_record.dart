import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/calls/call_half_in_flight.dart';
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
      required int chunksLost,
      required int chunksRefusedUnsubscribed,
      required int chunksSuppressed,
      required bool captureRefused,
      required bool drainComplete,
      String? langCode,
    });

/// Publishes this device's call-audio half, if it recorded one. See
/// `call_audio_recorder.dart`'s `CallAudioRecorder.finish`, which is what a
/// real caller wires this to.
///
/// Unlike [TranscriptPublisher], this carries no recording of its own to
/// hand over -- [callKey] is the only fact [CallRecord] itself has that the
/// recorder could not already have latched. Whether anything is actually
/// uploaded or sent is entirely the wired closure's decision: [CallRecord]
/// calls this UNCONDITIONALLY, on the same terms it calls
/// [publishTranscript], and trusts the closure to gate on the carrier fact
/// (`CallAudioRecorder.finish`'s `wasCarrier`) itself. See [_publishCallAudio]
/// for why the gate cannot live here instead.
typedef CallAudioPublisher = Future<void> Function({required String? callKey});

/// Finalises this device's recording LOCALLY -- no network -- before the
/// learner is credited: builds the WAV, starts the recording-based
/// transcription and the durable on-disk copy. See
/// `CallAudioRecorder.prepare`. [liveTranscriptContent] and [transcriptTxnId]
/// are the live transcript half, frozen into that durable copy so a resume
/// after a kill can still publish a half when none was built.
typedef CallAudioPreparer =
    Future<void> Function({
      required String? callKey,
      Map<String, dynamic>? liveTranscriptContent,
      String? transcriptTxnId,
    });

/// Builds -- without sending -- the live transcript half [TranscriptPublisher]
/// would send for these arguments, returning its content and transaction id,
/// or null when no half would be written.
typedef TranscriptContentBuilder =
    Future<({Map<String, dynamic> content, String txnId})?> Function({
      required String callKey,
      required List<TranscriptSegment> segments,
      required int chunksCaptured,
      required int chunksTranscribed,
      required int chunksLost,
      required int chunksRefusedUnsubscribed,
      required int chunksSuppressed,
      required bool captureRefused,
      required bool drainComplete,
      String? langCode,
    });

/// Supplies this device's whole-recording transcript segments when the
/// recording-based transcript feature is wired up. See
/// `CallAudioRecorder.recordingSegmentsReady`, which a real caller wires this
/// to; the wiring is gated on `Environment.callRecordingTranscript`, so a null
/// source here IS the feature being off. Waited on for at most
/// `CallRecord.recordingTranscriptDeadline`, read once, and preferred over the
/// live-chunk segments only when it returns a NON-EMPTY list in time -- empty,
/// late or failed means this device has no usable recording-based half, and
/// its live one stands.
typedef RecordingTranscriptSource =
    FutureOr<List<TranscriptSegment>> Function();

class CallRecord {
  final CallEventSender sendEvent;

  /// Publishes this device's transcript half, if the feature is wired up.
  ///
  /// Optional so every existing construction of a record keeps working
  /// unchanged, and so a deployment can leave transcripts unpublished without
  /// touching this class.
  final TranscriptPublisher? publishTranscript;

  /// Publishes this device's call-audio half, if the feature is wired up.
  /// Optional for the same reason [publishTranscript] is: every existing
  /// construction of a record keeps working unchanged, and a deployment can
  /// leave the recording unpublished without touching this class.
  final CallAudioPublisher? publishCallAudio;

  /// Supplies this device's recording-based transcript segments when that
  /// feature is wired up; null when it is off. See [RecordingTranscriptSource].
  /// Optional for the same reason [publishTranscript] is: every existing
  /// construction of a record keeps working unchanged, and with it null the
  /// class behaves exactly as it did before the feature existed.
  final RecordingTranscriptSource? recordingSegments;

  /// Runs the whole-call transcriber (#8792) for this call once this device's
  /// OWN half has been published -- the "post own half first" step. Optional and
  /// null on the default path: every existing construction keeps working
  /// unchanged, and the feature reverts by leaving it unwired. Invoked
  /// fire-and-forget with the call anchor, because the transcriber runs its own
  /// grace and bounded retries in the background and must never delay crediting
  /// or teardown. It gates itself on the flag and the invoker's live
  /// subscription, so this is called unconditionally when wired.
  final Future<void> Function(String callKey)? backfillPeerTranscripts;

  /// See [CallAudioPreparer]. Null keeps the record's flow as it was.
  final CallAudioPreparer? prepareCallAudio;

  /// See [TranscriptContentBuilder]. Null stores no live half for a resume.
  final TranscriptContentBuilder? buildLiveTranscript;

  /// The deterministic transaction ids of this device's two halves for a call
  /// key. When set, each half is claimed in [CallHalfInFlight] for as long as
  /// this finish works on it, so a resume or an outbox replay in the same
  /// process skips it instead of racing it.
  final String Function(String callKey)? audioTxnIdFor;
  final String Function(String callKey)? transcriptTxnIdFor;

  /// D_rec: how long the transcript half waits for the recording-based
  /// segments before the live half stands.
  final Duration recordingTranscriptDeadline;

  /// D_credit: how long publishing waits for the credit. Past it the credit
  /// keeps running and is never canceled; publishing simply stops waiting.
  final Duration creditDeadline;

  /// The bound on one transcript publish attempt on the recording-based path.
  /// A deadline parks the half: the outbox holds it for the next trigger.
  final Duration transcriptAttemptDeadline;
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
    this.publishCallAudio,
    this.recordingSegments,
    this.backfillPeerTranscripts,
    this.prepareCallAudio,
    this.buildLiveTranscript,
    this.audioTxnIdFor,
    this.transcriptTxnIdFor,
    this.recordingTranscriptDeadline = const Duration(seconds: 120),
    this.creditDeadline = const Duration(seconds: 15),
    this.transcriptAttemptDeadline = kCallHalfNetworkDeadline,
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

    /// Whether this device's microphone never opened. Distinct from a speaker
    /// who was muted: one is a fact about them, the other about us, and they
    /// reach the accounting as the same zero chunks unless told apart here.
    bool captureRefused = false,
    bool answered = true,
    bool declined = false,
    bool writeTimelineEvent = true,

    /// Whether this call earned any trace at all -- somebody was rung, or
    /// somebody arrived. A call that rang nobody and connected to nothing
    /// leaves NOTHING, and that is a fact about the call rather than about
    /// the record, so it is stated by the caller who watched it happen.
    ///
    /// Explicit because it used to be implied. The transcript below published
    /// before anything here had established the call was worth recording, and
    /// what kept a phantom call's half out of the room was a guard in the
    /// session and a chain of coincidences in the call underneath it: a ring
    /// that never went out also leaves no membership, so the key came through
    /// null and publishing skipped itself. That is three classes agreeing by
    /// luck about a rule none of them states. Defaulted true because every
    /// caller that reaches here at all has already decided the call happened;
    /// it is the refusal that has to be said out loud.
    bool mattered = true,
    String? anchorEventId,
    String? callerId,
    String? callKey,
  }) async {
    // Nothing at all, then: not the half below, not the credit, not the card
    // the retry path would otherwise write.
    if (!mattered) return;

    // CREDIT FIRST (#9302). The credit used to wait behind both publishes --
    // an upload of minutes of audio and a whole-recording speech-to-text pass
    // -- and a learner who closed the app in that window lost the call's
    // analytics. Now the order is:
    //
    // 1. claim this device's two halves, so a resume or an outbox replay in
    //    this process leaves them to us;
    // 2. finalise the recording LOCALLY (WAV, durable copy, transcription
    //    started) -- no network, so a kill from here on still leaves the
    //    recording on disk;
    // 3. credit, waiting at most [creditDeadline] (never canceled past it);
    // 4. publish the audio and transcript halves; then the peer backfill.
    //
    // Publishing still lives outside the credit's control flow: it needs only
    // the anchor, it is a separate promise to the learner, and a card that
    // failed to write must not cost the transcript.
    final audioHalf = _claimHalf(audioTxnIdFor, callKey);
    final transcriptHalf = _claimHalf(transcriptTxnIdFor, callKey);
    try {
      if (audioHalf.proceed) await _prepareAudio(callKey, captureRefused);

      if (!_credited) {
        final credit = _credit(
          duration: duration,
          video: video,
          answered: answered,
          declined: declined,
          writeTimelineEvent: writeTimelineEvent,
          anchorEventId: anchorEventId,
          callerId: callerId,
          callKey: callKey,
        );
        try {
          await credit.timeout(creditDeadline);
        } on TimeoutException {
          Logs().w(
            'The call credit is still running after '
            '${creditDeadline.inSeconds}s; publishing the halves meanwhile',
          );
        }
      }

      // Each half releases its own claim the moment it settles, so a half that
      // parks does not hold the other's.
      Future<void> audio() async {
        try {
          if (audioHalf.proceed) await _publishCallAudio(callKey);
        } finally {
          CallHalfInFlight.release(audioHalf.token);
        }
      }

      Future<void> transcript() async {
        try {
          if (transcriptHalf.proceed) {
            await _publishTranscript(callKey, captureRefused);
          }
        } finally {
          CallHalfInFlight.release(transcriptHalf.token);
        }
        // The own half is now posted -- "post own half first". Kick off the
        // whole-call transcriber for the peer's half. Fire-and-forget: it waits
        // its own grace and retries on its own schedule. It gates itself on the
        // flag and live subscription, and reverts by being unwired.
        final backfill = backfillPeerTranscripts;
        if (backfill != null && callKey != null) {
          unawaited(
            backfill(callKey).catchError((Object e, StackTrace s) {
              Logs().w('Whole-call peer transcription failed', e, s);
            }),
          );
        }
      }

      // With the recording-based transcript wired the two run side by side:
      // the transcript waits (bounded) only for the recording's SEGMENTS,
      // never for the upload, and the audio half's upload is bounded on its
      // own. With it off the original transcript-first order stands.
      if (recordingSegments != null) {
        await Future.wait([audio(), transcript()]);
      } else {
        await transcript();
        await audio();
      }
    } finally {
      CallHalfInFlight.release(audioHalf.token);
      CallHalfInFlight.release(transcriptHalf.token);
    }
  }

  /// Claims this device's half for [callKey] when [txnIdFor] is wired.
  /// `proceed` is false only when someone else in this process holds it.
  ({bool proceed, ClaimToken? token}) _claimHalf(
    String Function(String callKey)? txnIdFor,
    String? callKey,
  ) {
    final key = usableKey(callKey);
    if (txnIdFor == null || key == null) return (proceed: true, token: null);
    final token = CallHalfInFlight.claim(txnIdFor(key));
    if (token == null) {
      Logs().i('A call half is already being worked on; leaving it to them');
      return (proceed: false, token: null);
    }
    return (proceed: true, token: token);
  }

  /// Step 2 of [finish]: the recording is finalised and made durable before
  /// anything touches the network. Never throws.
  Future<void> _prepareAudio(String? callKey, bool captureRefused) async {
    final prepare = prepareCallAudio;
    if (prepare == null) return;
    ({Map<String, dynamic> content, String txnId})? live;
    final build = buildLiveTranscript;
    final key = usableKey(callKey);
    if (build != null && key != null && publishTranscript != null) {
      try {
        live = await boundedLocal(
          build(
            callKey: key,
            segments: transcripts.segments,
            chunksCaptured: transcripts.chunksCaptured,
            chunksTranscribed: transcripts.chunksTranscribed,
            chunksLost: transcripts.chunksLost,
            chunksRefusedUnsubscribed: transcripts.chunksRefusedUnsubscribed,
            chunksSuppressed: transcripts.chunksSuppressed,
            captureRefused: captureRefused,
            drainComplete: transcripts.drainComplete,
            langCode: transcripts.langCode,
          ),
          'freeze the live transcript half',
        );
      } catch (e, s) {
        Logs().w('Could not freeze the live transcript half', e, s);
      }
    }
    try {
      await prepare(
        callKey: callKey,
        liveTranscriptContent: live?.content,
        transcriptTxnId: live?.txnId,
      );
    } catch (e, s) {
      Logs().w('Finalising the call recording failed', e, s);
    }
  }

  /// The credit, joined by concurrent callers. See [finish].
  Future<void> _credit({
    required Duration duration,
    required bool video,
    required bool answered,
    required bool declined,
    required bool writeTimelineEvent,
    required String? anchorEventId,
    required String? callerId,
    required String? callKey,
  }) {
    // Concurrent callers join the in-flight attempt rather than being dropped.
    // Dropping one made a failed write unretryable in practice: the two callers
    // are the same hangup, and the discarded one was the only other chance.
    return _inFlight ??= () async {
      // The cause of the LAST attempt, so the report below can carry it. Null
      // when every attempt returned without throwing and the credit still did
      // not land -- an anchor that was never written, which is a failure with
      // no exception to name.
      Object? lastError;
      StackTrace? lastStack;
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
            lastError = e;
            lastStack = s;
            Logs().w(
              'Recording the call failed (attempt ${attempt + 1})',
              e,
              s,
            );
          }
        }
        if (!_credited) {
          Logs().e('Gave up recording this call; its analytics are lost');
          // The learner spoke and earned nothing for it. Like the half above,
          // this leaves NOTHING behind: uncredited speech is indistinguishable
          // from a call in which nobody said anything, and the proficiency
          // drawn from those counts is quietly short by a whole conversation.
          //
          // Keyed per call for the same reason: three attempts are one loss,
          // and two calls are two.
          ErrorHandler.logErrorOnce(
            key: '$analyticsLostKey:${callKey ?? _txid}',
            // The caught cause wherever there is one, so its runtime type
            // reaches the severity table and the fingerprint intact. The
            // sentence stands in ONLY for the branch that threw nothing -- an
            // anchor that was never written -- because a description the
            // reporter is not given as `e` reaches `debugPrint` and nowhere
            // else (#8660), and that branch would otherwise have no alarm at
            // all. Where there is a cause it owns the title; `anchored` below
            // is what tells the two branches apart in the event.
            e:
                lastError ??
                Exception(
                  "This call's speech was never credited to the learner",
                ),
            s: lastStack,
            data: {
              // Whether there was anything to anchor the uses to at all, which
              // is the one branch that reaches here without an exception.
              'anchored': _anchorId != null,
              'answered': answered,
              'seconds': duration.inSeconds,
            },
          );
        }
      } finally {
        _inFlight = null;
      }
    }();
  }

  /// The session-throttle key the uncredited-speech report is filed under, minus
  /// the call it is about.
  static const analyticsLostKey = 'call_record.analytics_lost';

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
  /// Publishes this device's half, retrying a transient failure.
  ///
  /// The retry is HERE and not shared with the card's. Publishing was moved out
  /// of `_finish` so a failed card could not cost the transcript and so the
  /// credit guard could not make it unreachable -- both real couplings -- but
  /// moving it out took it out of the card's retry loop as well, and nothing
  /// replaced that. The flag below was reset on failure so a later attempt
  /// could try again, the log said so, and no later attempt existed: `finish()`
  /// runs once per call behind a latch, and the screen is gone afterwards.
  /// Permitting a retry is not the same as performing one.
  ///
  /// A resend is safe because the transaction id is deterministic in
  /// (call_key, sender, device): a half that did land is collapsed by the
  /// server rather than written twice. That property is what makes retrying the
  /// correct answer here, and it is why refusing to retry was never buying
  /// anything -- duplicates were already impossible, so the refusal only threw
  /// the half away. A speaker whose one send failed then reads as ABSENT: told
  /// they said nothing, when they spoke and their device tried to say so.
  ///
  /// The property is only worth anything if every attempt actually produces
  /// that id, so THE PUBLISHER MUST NOT READ THE ACCOUNT OR THE DEVICE PER
  /// ATTEMPT. `CallSession` latches both when it builds the publisher; a
  /// publisher that read them off the live client instead would send the retry
  /// of a signed-out device under a different key, which is a second event
  /// carrying the same speech.
  Future<void> _publishTranscript(String? callKey, bool captureRefused) async {
    final publish = publishTranscript;
    if (publish == null || _published || callKey == null) return;

    // Read ONCE, before the first attempt. The sink is closed by now, and a
    // retry must resend the same half rather than whatever the sink reports
    // later -- the deterministic transaction id only collapses a resend if the
    // resend is actually the same event.
    //
    // The recording-based segments when this device produced them, else the
    // live 45-second chunks. An empty source -- feature off, no recording, or a
    // failed transcription -- means this device has no recording-based half and
    // its live one stands, which is the per-half fault tolerance the design
    // rests on. Only the SEGMENTS switch source; the capture accounting below
    // still reports the live chunk path's health, unchanged.
    // Marked before the first await so concurrent callers cannot both publish.
    _published = true;

    // Waited for, BOUNDED by [recordingTranscriptDeadline], and read once. Past
    // the deadline -- or with no segments, or a failure -- the live half
    // stands; the reason is logged so a fallback is never silent.
    var recorded = const <TranscriptSegment>[];
    final source = recordingSegments;
    if (source != null) {
      String reason;
      try {
        recorded = await Future.value(
          source(),
        ).timeout(recordingTranscriptDeadline);
        reason = recorded.isNotEmpty
            ? 'recording'
            : 'live (the recording produced no segments)';
      } on TimeoutException {
        reason =
            'live (the recording was not transcribed within '
            '${recordingTranscriptDeadline.inSeconds}s)';
      } catch (e, s) {
        reason = 'live (the recording transcription failed)';
        Logs().w('Reading the recording-based segments failed', e, s);
      }
      Logs().i('Call transcript half source: $reason');
    }
    final segments = recorded.isNotEmpty ? recorded : transcripts.segments;
    final chunksCaptured = transcripts.chunksCaptured;
    final chunksTranscribed = transcripts.chunksTranscribed;
    final chunksLost = transcripts.chunksLost;
    final chunksRefusedUnsubscribed = transcripts.chunksRefusedUnsubscribed;
    final chunksSuppressed = transcripts.chunksSuppressed;
    // Meaningful only once the sink has closed, which the capture service does
    // before this runs. Read earlier it would be the optimistic default and a
    // half could claim a completeness nothing had checked.
    final drainComplete = transcripts.drainComplete;
    final langCode = transcripts.langCode;

    // Kept so the report at the bottom can carry the CAUSE. Each attempt logs
    // its own failure, but only the last one is worth an event -- and an event
    // titled by a hand-written sentence says what was lost and nothing
    // whatever about why.
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(seconds: attempt));
      Future<void> send() => publish(
        callKey: callKey,
        segments: segments,
        chunksCaptured: chunksCaptured,
        chunksTranscribed: chunksTranscribed,
        chunksLost: chunksLost,
        chunksRefusedUnsubscribed: chunksRefusedUnsubscribed,
        chunksSuppressed: chunksSuppressed,
        captureRefused: captureRefused,
        drainComplete: drainComplete,
        langCode: langCode,
      );
      final attemptToken = AttemptToken();
      try {
        if (source == null) {
          await send();
        } else {
          // Bounded on the recording-based path, where the outbox holds the
          // built half: a deadline parks it there for the next trigger, and the
          // dead attempt token stops a late confirmation from dropping it.
          await attemptToken.run(
            () => raceBounded(
              send(),
              deadline: transcriptAttemptDeadline,
              step: 'publish the transcript half',
              attempt: attemptToken,
            ),
          );
        }
        return;
      } on CallHalfParked catch (e) {
        Logs().w(
          'Publishing the call transcript parked at "${e.step}"; the outbox '
          'replays it on the next launch or foreground',
        );
        return;
      } catch (e, s) {
        // Swallowed rather than rethrown, so a transcript failure cannot drag
        // the credit into its own retry loop, which is once-only and cannot
        // survive being re-entered.
        lastError = e;
        lastStack = s;
        Logs().w('Publishing the call transcript failed', e, s);
      } finally {
        attemptToken.live = false;
      }
    }

    // Every attempt failed. Released so anything that does call again may try,
    // and logged as a LOSS rather than as a retryable condition -- the previous
    // wording claimed a retry that nothing performed.
    _published = false;
    Logs().e(
      'The call transcript was not published after 3 attempts; '
      'this speaker will read as absent',
    );
    // AND COUNTED. A half that does not publish makes this speaker read as
    // absent, which is the SAME reading as a device that never ran the feature
    // at all -- so nothing anywhere knows how many calls should have produced
    // two halves and produced one. That number is the whole point of reporting
    // this: the loss is invisible in the data it leaves behind, and only the
    // device that suffered it can say it happened.
    //
    // ONCE PER CALL, not per attempt and not per session. The three attempts
    // above are one loss and belong in one event; two calls that each lost
    // their half are two losses and each is owed its own, because the count of
    // them is what is being asked for. [_published] is released above, so a
    // later finish can try and fail again -- and that is the same loss, which
    // the key collapses.
    ErrorHandler.logErrorOnce(
      key: '$transcriptNotPublishedKey:$callKey',
      // The last attempt's cause, which every path that reaches here has: the
      // loop only falls through by throwing three times. The sentence is the
      // fallback the type demands rather than a case that happens -- and it is
      // the right fallback, because a report with no exception would otherwise
      // carry nothing a search could find.
      e:
          lastError ??
          Exception(
            'This device published no transcript half; the speaker will read '
            'as absent from a call they spoke in',
          ),
      s: lastStack,
      // COUNTS AND SIZES, never a word of it. What was said is the learner's,
      // and Sentry is not where it belongs -- but how MUCH was lost is what
      // tells a dropped connection at hangup from a half that was empty anyway.
      data: {
        'segments': segments.length,
        'bytes': segments.fold<int>(
          0,
          (sum, segment) => sum + utf8.encode(segment.text).length,
        ),
        'chunksCaptured': chunksCaptured,
        'chunksTranscribed': chunksTranscribed,
        'chunksLost': chunksLost,
        'chunksRefusedUnsubscribed': chunksRefusedUnsubscribed,
        'chunksSuppressed': chunksSuppressed,
        'captureRefused': captureRefused,
        'drainComplete': drainComplete,
      },
    );
  }

  /// The session-throttle key the unpublished-half report is filed under, minus
  /// the call it is about. Named so the report and its budget test agree.
  static const transcriptNotPublishedKey =
      'call_record.transcript_not_published';

  bool _published = false;

  /// Calls [publishCallAudio], swallowing any failure.
  ///
  /// Unconditional, on the same terms [_publishTranscript] is called
  /// unconditionally above it: this runs on EVERY device's `finish()`,
  /// including one that never carried the recording at all, and including
  /// one for a call that never connected. `finish()` is reached this way
  /// from `CallSession`'s teardown regardless -- see
  /// `CallCaptureService.wasCarryingBeforeLastStop`'s own docs for why that
  /// is unavoidable rather than a bug this class could fix by checking
  /// something first.
  ///
  /// The gate belongs in the wired closure, never here, because ONLY the
  /// closure -- `CallAudioRecorder.finish` -- can answer "was this device
  /// carrying" at the one moment that answer is trustworthy, and can go on
  /// re-checking it through an upload still in flight. A gate written here
  /// instead would have to trust a snapshot taken earlier and handed in,
  /// which is exactly the gap the recording feature's own design docs warn
  /// against inheriting from this method's identical-looking transcript
  /// sibling.
  Future<void> _publishCallAudio(String? callKey) async {
    final publish = publishCallAudio;
    if (publish == null) return;
    try {
      await publish(callKey: callKey);
    } catch (e, s) {
      Logs().w('Publishing the call audio half failed', e, s);
    }
  }

  /// How long a call in the timeline lasted, read from its content.
  ///
  /// Defensive because this event is written by other clients and by older
  /// versions of this one: a cast that throws while drawing the timeline takes
  /// down the whole row rather than one number in it.
  static Duration? durationOf(Map<String, Object?> content) {
    // Finite, not merely parseable. `num.tryParse` accepts "NaN" and
    // "Infinity", and `.round()` on either throws -- so a card carrying one of
    // those words took the whole row down rather than reading as a call of
    // unknown length. Room content, so it is somebody else's word.
    final ms = content['duration_ms'];
    final parsed = ms is num
        ? ms
        : ms is String
        ? num.tryParse(ms)
        : null;
    // Non-negative as well as finite. A call cannot have lasted less than no
    // time, and the value is somebody else's word.
    if (parsed != null && parsed.isFinite && parsed >= 0) {
      return Duration(milliseconds: parsed.round());
    }
    // Null, not zero. A card stating no usable length and a call that really
    // lasted none are different facts, and collapsing them made one surface
    // print "0:00" for a malformed card while the other printed nothing -- a
    // length the data does not support, and two views of one call disagreeing.
    return null;
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

  /// A key a call can actually be identified by, or null.
  ///
  /// EMPTY IS NOT A KEY. Two cards both carrying '' are not two sightings of
  /// one call; they are two calls whose identity was never learned. Reading
  /// the empty string as a shared identity made the later of two such calls
  /// count as a duplicate of the earlier one and disappear from the
  /// conversation, taking its transcript's only tap target with it.
  ///
  /// The transcript half has always drawn this line -- CallTranscriptContent
  /// refuses an empty key outright -- and the card's own read of the field
  /// drew it too. The two places that decide whether two cards are the SAME
  /// call did not, so one surface treated a value as an identity while
  /// another treated it as nothing. This is that one line, drawn once, for
  /// everything that reads or writes the field.
  static String? usableKey(String? key) =>
      key != null && key.isNotEmpty ? key : null;

  /// The usable call key a card's content carries, or null.
  ///
  /// Defensive about the type as well as the emptiness: this is somebody
  /// else's word, written by other clients and older versions of this one, and
  /// a number where a string belongs must read as "no key" rather than take
  /// the timeline row down.
  static String? keyOf(Map<String, Object?> content) {
    final key = content[callKeyField];
    return key is String ? usableKey(key) : null;
  }

  Future<String?> _write({
    required Duration duration,
    required bool video,
    required bool answered,
    required bool declined,
    required String? callerId,
    required String? callKey,
  }) async {
    // A card cannot state a negative length. What this is measured from is the
    // wall clock, and a step backwards mid-call -- an NTP correction, a
    // learner changing the time on their phone -- makes the subtraction
    // negative. The stamp below cannot express that: it renders one second
    // short of nothing as "0:59", which is a plausible duration and
    // indistinguishable afterwards from a real one. Clamped once, here, so the
    // readable fallback and the number cannot disagree either.
    final length = duration.isNegative ? Duration.zero : duration;
    // See [usableKey]: an empty key identifies nothing, so it is left out
    // altogether rather than stamped as an identity every reader would then
    // have to know to disbelieve.
    final key = usableKey(callKey);
    try {
      return await sendEvent(<String, dynamic>{
        'msgtype': PangeaEventTypes.call,
        // The plaintext fallback every Matrix client falls back to when it does
        // not understand the msgtype. Without it a call reads as an empty
        // message everywhere but here.
        'body': _fallbackText(
          duration: length,
          video: video,
          answered: answered,
          declined: declined,
        ),
        'duration_ms': length.inMilliseconds,
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
        callKeyField: ?key,
      }, _txid);
    } catch (e, s) {
      Logs().e('Could not write the call to the room', e, s);
      return null;
    }
  }
}
