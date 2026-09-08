import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_recorder.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_tap.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

/// Where a completed chunk goes.
///
/// An interface rather than a direct HTTP call so the capture path can be tested
/// by feeding it audio and reading back what it produced, and so a delivery
/// failure is the sink's problem rather than the recorder's.
abstract class CallAudioSink {
  /// Delivers one chunk. Safe to call again with the same chunk: the server keys
  /// a result by capture session and chunk index, so a redelivery credits
  /// nothing twice.
  ///
  /// [within] is how long the attempt itself may take. Given to the sink rather
  /// than applied by the caller because it has to bound the WORK: a caller that
  /// merely stopped waiting leaves the attempt running, and a retry that joins
  /// it is not a second attempt at all.
  Future<void> deliver(PcmChunk chunk, {Duration? within});

  /// Records a chunk this recorder captured and deliberately did NOT deliver,
  /// because another of this account's devices was recording the same stretch.
  ///
  /// Not a delivery and not a failure, so it belongs in neither [deliver] nor
  /// its error path: the audio was read, cut, and then set aside on purpose.
  /// It is here so that the sink's accounting still knows the chunk existed.
  /// Without it the chunk was in no count at all -- the half published a clean
  /// record of a stretch it had thrown away, and nothing downstream could tell
  /// a correct discard from a wrong one, in either direction.
  ///
  /// Synchronous, and never fails: it records a fact rather than performing
  /// work, and it is called from the flush that ends a run, where an
  /// unawaited future would be an unhandled error at a hangup.
  void discarded(PcmChunk chunk);

  /// Signals that no further chunks are coming for this call.
  ///
  /// Returns whether every outstanding transcription settled. FALSE means the
  /// sink gave up on work still in flight, so what it holds is knowingly short
  /// of what was said. It used to return nothing and merely log that, which
  /// left the one caller that publishes a transcript unable to tell a complete
  /// half from a truncated one -- and a half that quietly claims to be
  /// everything somebody said is the one outcome this feature cannot produce.
  Future<bool> close();
}

/// The audio format chunks are captured and delivered in.
///
/// 16 kHz mono is what speech-to-text providers accept natively, so nothing
/// downstream resamples, and it keeps a chunk small enough that the route's
/// request cap is never the binding constraint.
const captureSampleRate = 16000;
const captureChannels = 1;

/// The first retry's backoff. Each retry after it doubles the wait, up to
/// [_deliveryBackoffCeiling].
///
/// A chunk is up to ninety seconds of somebody's speech and there is no second
/// copy — the call is over by the time delivery fails, and nothing can record
/// it again. So a transient blip — a 429, a 5xx, a dropped packet — must not
/// cost the whole of it: the delivery is retried, gently, until it lands or the
/// call's own finish window ([_deliveryRetryBudget]) runs out.
const _deliveryBackoffBase = Duration(milliseconds: 500);

/// The largest a single retry's backoff grows to before jitter. Doubling from
/// 500 ms reaches it at the fifth wait, so the sequence is 0.5, 1, 2, 4, 8, 8,
/// 8 … seconds — long enough to outlast the upload gate's open window
/// ([CallUploadGate.openFor], 15 s) several times over, short enough that a
/// recovering backend is retried promptly rather than after a minute of
/// silence.
const _deliveryBackoffCeiling = Duration(seconds: 8);

/// How much of a backoff jitter may add on top, as a fraction. A whole fleet of
/// devices that failed on the same backend blip would otherwise retry in
/// lockstep and re-hammer it the instant its cooldown ends; spreading each
/// device's wait by up to a quarter breaks that synchronisation without
/// meaningfully lengthening any one device's own recovery.
const _deliveryBackoffJitter = 0.25;

/// How long one attempt at delivering a chunk is given.
///
/// A request that fails says so; one that hangs says nothing, and a hangup waits
/// for every chunk still in flight. Without a limit here a single stalled
/// connection would hold the end of the call open indefinitely.
const _deliveryTimeout = Duration(seconds: 30);

/// How long a stop waits for chunks already handed over.
///
/// Long enough for an ordinary delivery and its first retry, short enough that
/// a stuck upload cannot hold up the next stretch of recording.
const _settleDeliveriesWithin = Duration(seconds: 10);

/// How long the END of a call waits for deliveries still in flight. Generous —
/// it covers a delivery's full retry budget — because this is the last chance
/// for the words to land; but finite, because a record that never appears is
/// worse than one slightly short.
const _settleFinishWithin = Duration(minutes: 2);

/// How long the WHOLE retry sequence for one chunk may run before it is given
/// up on as lost.
///
/// The same window [finish] waits out, and deliberately so: a retry sequence
/// bounded by the finish window can span the upload gate's open window many
/// times over — giving a transient burst time to pass and the backend time to
/// recover — yet can never run past the end of the call or hold a hangup open,
/// because a chunk is handed over no later than the call's own last flush and
/// [finish] waits at least this long from that same point. The reserve in
/// [CallCaptureService._deliver] keeps even the last attempt's own timeout
/// inside this budget, so the sequence never overshoots it.
const _deliveryRetryBudget = _settleFinishWithin;

/// Backs the default delivery-retry jitter. One per process is plenty: only the
/// spread of the values matters, never their exact sequence.
final _deliveryJitter = math.Random();

/// How long a tap is given to come off before it is treated as stuck.
///
/// Detaching is a platform call and should take no time at all, but teardown
/// waits on it — and a hangup that never finishes never writes the call, so the
/// learner loses both the record and every word of the conversation.
const _detachTimeout = Duration(seconds: 5);

/// The wall clock, in absolute Unix milliseconds.
int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

/// A process-wide MONOTONIC millisecond counter.
///
/// Only differences are ever taken from it, so its origin does not matter and
/// one shared stopwatch costs less than one per recorder. Unlike the wall clock
/// it cannot be corrected out from under a call.
final _uptime = Stopwatch()..start();
int _systemElapsedMs() => _uptime.elapsedMilliseconds;

/// Records this device's own outbound call audio.
///
/// It taps the track being published, not the microphone. A microphone also
/// hears the peer coming back out of the speaker, and every word that bled
/// through would be credited to the wrong learner — so the tap point is the
/// requirement, not an implementation preference.
///
/// One recorder per call. Starting a second while one runs is a caller error
/// rather than a silent second recording.
class CallCaptureService {
  final CallAudioSink sink;
  final CallAudioTap tap;
  final Duration deliveryTimeout;

  /// How long [finish] waits for deliveries still in flight before it stops
  /// waiting and closes the sink. Injected beside [deliveryTimeout] so a test can
  /// drive finish's give-up -- and the teardown cancellation that follows it --
  /// deterministically, instead of waiting out the real window in wall time.
  /// Defaults to [_settleFinishWithin], the production two minutes; production
  /// never passes anything else, so the delivery retry budget and this wait stay
  /// the one window they are documented to be.
  final Duration finishSettleWithin;

  /// A second, independent consumer of this device's own outbound audio: the
  /// call-audio-recording half. Optional, so every existing construction of a
  /// recorder keeps working unchanged and a deployment can leave the feature
  /// unwired without touching this class.
  ///
  /// Fed from the exact same tap this class already owns, never a second
  /// attach: a tap is exclusive per platform (see [PostEchoCancellationTap],
  /// [TrackRendererTap]) and a second `tap.open` would either be refused or
  /// double-count the learner's own audio. See [_onFrames] and [_endRun] for
  /// where this is called, and [wasCarryingBeforeLastStop] for the one fact
  /// about this device's own lifecycle it needs that nothing else exposes.
  final CallAudioRecordingSink? audioRecording;

  /// How long a tap is given to detach. Injected so a test need not wait it out.
  final Duration detachTimeout;

  /// The wall clock, read exactly ONCE per call. Injected because the rules
  /// below exist to survive a clock that misbehaves, which is not reachable
  /// from a test any other way.
  final int Function() nowMs;

  /// A monotonic millisecond counter, used only for differences.
  ///
  /// Injected beside [nowMs] so a test can advance wall time and elapsed time
  /// independently — which is the only way to tell this mechanism apart from
  /// the floor that backs it up.
  final int Function() elapsedMs;

  /// Waits [d] before a delivery retry. Injected so a test can advance the
  /// backoff instantly rather than sleeping through it — and, because the same
  /// [elapsedMs] clock bounds the retry sequence, a test's wait can move that
  /// clock so the budget it enforces is exercised deterministically. Defaults to
  /// a real [Future.delayed] in production, where real time passes on both.
  final Future<void> Function(Duration d) _delay;

  /// A jitter source in [0, 1), added to each backoff (see
  /// [_deliveryBackoffJitter]). Injected — and seedable — so the exponential
  /// backoff a test observes is deterministic rather than random. Defaults to a
  /// shared [math.Random].
  final double Function() _jitter;

  final PcmChunker Function(
    int firstIndex,
    int sampleRate,
    int channels,
    int runStartedAtMs,
  )
  _newChunker;

  /// Chunk numbering continues across stop and start. Recording can be handed to
  /// another of the learner's devices and handed back within one call, and a
  /// second stretch numbered from zero would be taken for a redelivery of the
  /// first and silently dropped.
  int _nextIndex = 0;

  /// Where the run just closed ended, in absolute Unix milliseconds.
  ///
  /// A FLOOR, not a guess. The next run's audio cannot have been captured
  /// before the previous run's audio finished, so taking the later of this and
  /// the clock makes a half monotone by construction: a device clock that steps
  /// backwards mid-call can compress a gap to zero, but it can never move a
  /// later run in front of an earlier one.
  ///
  /// Zero until a run has closed, which is no constraint at all — there is
  /// nothing yet for a first run to have to sit after.
  int _notBeforeMs = 0;

  PcmChunker? _chunker;
  DetachTap? _detach;

  /// The format the currently-open call-audio-recording run was opened with,
  /// or null when no run is open for it right now.
  ///
  /// Tracked SEPARATELY from [_chunker] on purpose. The transcript chunker's
  /// own run ends on a mute -- a mute is a gap in the transcript, which is
  /// what a mute should be -- but the recording's run must NOT: it wants a
  /// CONTINUOUS file with silence standing in for a mute, so gating the
  /// recording's own run-boundary on [_chunker] (as an earlier version did)
  /// meant a call that started muted, or was muted for its very first frame,
  /// never opened a recording generation at all -- [_chunker] simply never
  /// existed yet to compare against, `forThisRun` was false, and the whole
  /// branch that would have opened one was never reached. This field is
  /// updated independently, gated on [recorderLive] alone, so a muted call's
  /// very first frame still opens a generation and records silence from the
  /// first millisecond onward.
  ({int sampleRate, int channels})? _audioRunFormat;

  /// Whether the last attempt to OPEN a recording run threw. Latched so the
  /// per-frame retry (in [_onFrames]'s run-open block) logs a failure once per
  /// streak rather than on every frame, and cleared the moment a run opens.
  bool _runStartFailed = false;

  /// Whether the current stretch has stopped taking frames.
  ///
  /// Set before the detach rather than after it, and cleared only by the next
  /// [start], so it marks the whole span between a stretch ending and one
  /// replacing it. Two things read it, for the same reason: frames arriving in
  /// that span belong to no stretch, and so does a discard request.
  bool _stopping = false;

  /// Whether a tap is attached. Separate from having a chunker, because the rate
  /// is not known until audio actually arrives.
  bool _running = false;

  /// Which stretch of recording this is. Attaching a tap takes a round trip and
  /// a stop can land inside it; comparing this afterwards is how that stop is
  /// noticed, rather than storing a tap nothing is left tracking.
  int _session = 0;

  /// How many releases are working on a tap right now.
  ///
  /// A tap is UNACCOUNTED FOR from the moment a release starts on it until it
  /// has a definite home again — let go cleanly, or moved into [_unreleased].
  /// Across that span [_detach] is already null and [_unreleased] is still
  /// empty, so both of the questions the rest of this class asks about held
  /// taps answer "nothing attached" about a tap that is very much attached.
  ///
  /// A counter rather than a flag because releases nest: [_releaseUnreleased]
  /// calls [_release] for each entry it retries.
  ///
  /// Deliberately NOT extended over `tap.open`. [_running] is set before the
  /// open, so the attach window is already covered, and an in-flight attach is
  /// a millisecond timing race rather than anything true about the device.
  int _releasing = 0;

  /// The release of a tap that arrived after the stop it belonged to, which is
  /// the one release that runs OUTSIDE the memoised stop.
  ///
  /// [_stop] waits for it before retrying residue, so a stop cannot walk past a
  /// tap that is about to be held: only a stop ever comes back to one, and a
  /// tap held after the last stop of the call is held for good.
  Future<void>? _releasingWork;

  /// How many taps this device has attached that then delivered nothing.
  ///
  /// CONSECUTIVE. A run that produces audio clears it, because a delivered
  /// frame is the only evidence available that an attempt can differ from the
  /// one before it. Never cleared by a stop: the death itself stops, so a reset
  /// there would count nothing at all.
  int _tapDeaths = 0;

  /// How many of those are attempted before this device stops attaching taps.
  ///
  /// A death ends the stretch and re-runs the election, and until the deaths
  /// reach this limit [canCapture] is still true — so the device that just
  /// failed wins the election again and attaches the same tap for the same
  /// reason. Nothing between the attempts differs, which makes repeating it a
  /// spin rather than a retry beyond a point: on the web
  /// every turn builds and tears down an AudioContext and an AudioWorklet
  /// module, and on native it is a platform round trip each way, for the rest of
  /// the call.
  ///
  /// Two, because the first death can honestly be a transient — a browser that
  /// stalled an AudioContext resume before it had a user gesture and has one by
  /// the second attempt. A third attempt after two identical failures is not
  /// evidence of anything.
  ///
  /// Past it, [start] returns having attached nothing, which is the answer a
  /// device with no tap point already gives: [isRecording] stays false, the
  /// election settles, and the log says once that this device is out. It also
  /// turns [canCapture] false, which is how a sibling that CAN record comes to
  /// out-rank this device rather than deferring to it on device id.
  static const _tapDeathLimit = 2;

  /// Whether the platform has answered that this device has no working tap
  /// point. Structural, and re-derived by every attach that gets far enough to
  /// hear an answer.
  bool _canCapture = true;

  /// Whether this device can record RIGHT NOW.
  ///
  /// One boolean, read by the election, and false only ever because of a
  /// CONCLUSION ABOUT THE DEVICE: a platform that answered it has no tap point,
  /// residue that survived a retry, or taps that attached and delivered nothing
  /// often enough that another attempt is a spin rather than a retry.
  ///
  /// Deliberately NOT false for a bad moment. A throw from the attach is a
  /// transient, and so is a refusal whose only cause is a release still in
  /// flight — publishing either as incapacity would have a healthy device stand
  /// aside for the rest of a call over a millisecond of timing.
  ///
  /// True is the DEFAULT everywhere, including on a device that has never
  /// tried: silence has to read as able, or the first election of a call would
  /// have every device defer to every other one.
  bool get canCapture => _canCapture && _tapDeaths < _tapDeathLimit;

  /// Whether the tail of the current stretch is to be dropped instead of
  /// delivered.
  ///
  /// A LEVEL-TRIGGERED REQUEST, written by whoever runs the election at the
  /// moment it decides, and read at the flush. It is not an argument to [stop]
  /// for two reasons. Teardown stops the recorder directly, outside the
  /// election's own serialised chain, so a stop can reach the flush while the
  /// election's reconcile is still queued — an argument would arrive after the
  /// audio had already gone. And a memoised stop hands the first caller's
  /// arguments to the second, so a handover's discard would have become a
  /// hangup's.
  ///
  /// Only ever the TAIL: a chunk the chunker's own size or silence ceiling
  /// already cut and handed to the sink earlier in this stretch is gone and is
  /// not chased.
  ///
  /// AND IT DESCRIBES A STRETCH, so it stops taking new answers at the same
  /// line the stretch stops taking frames. [_stop] reaches the flush only after
  /// up to three bounded platform waits — a detach, an overtaken start's
  /// release, and the residue sweep — and the election re-runs on a two second
  /// clock throughout. Left writable across that stall, the value read at the
  /// flush could belong to an election that ran seconds after the stretch
  /// ended, describing a roster with nothing to do with the audio being
  /// flushed: cleared inside the stall it delivers the duplicate, and set
  /// inside it, it drops the only copy of what the learner said.
  bool _discardOnStop = false;

  /// Records that this stretch's tail is a duplicate of what another of this
  /// account's devices already has.
  ///
  /// Ignored once the stretch has stopped taking frames, because from that line
  /// on there is no stretch left for a caller to be describing. The next [start]
  /// opens the question again.
  void setDiscardOnStop(bool discard) {
    if (_stopping) return;
    _discardOnStop = discard;
  }

  /// Told that the tap this recorder was running has died on its own.
  ///
  /// Set by whoever owns the election. A stop this side performed by itself
  /// leaves the owner's bookkeeping describing a recording that no longer
  /// exists, and an owner that caches "I am recording" then has no reason ever
  /// to start again. This is how the death reaches it.
  void Function()? onCaptureLost;

  /// Chunks handed to the sink but not yet acknowledged. Awaited on [stop] so a
  /// hangup does not abandon audio the learner already spoke.
  final List<Future<void>> _inFlight = [];

  /// Set once the call is tearing down and any outstanding delivery retry must
  /// stop. Read by [_deliver] before each attempt and after each backoff, and
  /// raised by [cancelOutstandingDeliveries]. Latching, and never cleared: a
  /// service is built per call and finished exactly once, so there is nothing
  /// after teardown for a cleared flag to matter to.
  bool _deliveriesCancelled = false;

  /// How much of this call's audio the capture path lost before it could be
  /// cut into a chunk, in milliseconds.
  ///
  /// Reported BY the tap, and only by a tap that accounts for its own drops.
  /// It is a different fact from every count the sink keeps: those are all
  /// about chunks, and this audio never became one -- so it is invisible to
  /// `chunksCaptured`, `chunksLost` and `chunksSuppressed` alike, and a half
  /// that carried only those read as complete over a hole in the recording.
  ///
  /// Per call, never reset, because a half describes a call rather than a
  /// stretch of one.
  int get captureDroppedMs => _captureDroppedMs;
  int _captureDroppedMs = 0;

  /// The stretches of this call this device captured and KEPT, in the order
  /// they were recorded.
  ///
  /// One per run: a run is the uninterrupted span between a first frame and
  /// whatever ends it, and its extent comes from the chunker's own exact frame
  /// arithmetic rather than from stitching the chunks back together — a sum of
  /// per-chunk durations truncates once per chunk, and a millisecond crack
  /// between two stretches that were in fact continuous would read as a gap in
  /// the coverage the half publishes.
  ///
  /// The tail a run handed to a sibling is CUT OFF this span and appears in
  /// [discardedSpans] instead, so the two lists never describe the same
  /// millisecond twice.
  ///
  /// Lives here rather than in the sink for the reason [captureDroppedMs] does:
  /// this is what the CAPTURE path knows, and the sink counts chunks.
  List<CaptureSpan> get keptSpans => List.unmodifiable(_keptSpans);
  final List<CaptureSpan> _keptSpans = [];

  /// The stretches this device captured and deliberately did not send, because
  /// another of the account's devices was recording them.
  ///
  /// The extent behind the sink's `chunksDiscarded`, which is a count and names
  /// no stretch. It is the whole reason a reader can ask whether the belief
  /// that authorised the discard held: without it, a discard could only be
  /// excused by a sibling having WRITTEN something, which is not the same as a
  /// sibling having HELD this stretch.
  List<CaptureSpan> get discardedSpans => List.unmodifiable(_discardedSpans);
  final List<CaptureSpan> _discardedSpans = [];

  /// Records one finished run: what it kept, and what it handed over.
  ///
  /// [handedOverFrom] is where the discarded tail begins, or null when nothing
  /// was handed over. A run whose whole audio went to a sibling keeps nothing,
  /// and states nothing: [CaptureSpan.of] refuses the empty stretch rather than
  /// publishing a point.
  void _recordRun({required int from, required int to, int? handedOverFrom}) {
    _record(_keptSpans, from, handedOverFrom ?? to);
    if (handedOverFrom != null) _record(_discardedSpans, handedOverFrom, to);
  }

  /// Adds one stretch, or nothing when it is not a stretch this writer may
  /// state.
  ///
  /// Bounded one past `CallTranscriptContent.maxSpans`, which is where a list
  /// stops being a statement this reader will act on. Past that point the event
  /// omits the field whatever else is added, so the entries are not merely
  /// unnecessary — recording them would be an unbounded list held for the
  /// length of a call to make a decision that has already been made.
  static void _record(List<CaptureSpan> into, int fromMs, int toMs) {
    if (into.length > CallTranscriptContent.maxSpans) return;
    final span = CaptureSpan.of(fromMs: fromMs, toMs: toMs);
    if (span != null) into.add(span);
  }

  /// [deliveryTimeout] is how long one attempt is given before it is treated as
  /// failed. Injectable so the stall can be tested without waiting for it.
  CallCaptureService({
    required this.sink,
    CallAudioTap? tap,
    this.audioRecording,
    this.deliveryTimeout = _deliveryTimeout,
    this.finishSettleWithin = _settleFinishWithin,
    this.detachTimeout = _detachTimeout,
    int Function()? nowMs,
    int Function()? elapsedMs,
    Future<void> Function(Duration d)? delay,
    double Function()? jitter,
    PcmChunker Function(
      int firstIndex,
      int sampleRate,
      int channels,
      int runStartedAtMs,
    )?
    newChunker,
  }) : tap =
           tap ??
           defaultCallAudioTap(
             sampleRate: captureSampleRate,
             channels: captureChannels,
           ),
       nowMs = nowMs ?? _systemNowMs,
       elapsedMs = elapsedMs ?? _systemElapsedMs,
       _delay = delay ?? ((d) => Future<void>.delayed(d)),
       _jitter = jitter ?? _deliveryJitter.nextDouble,
       _newChunker =
           newChunker ??
           ((firstIndex, sampleRate, channels, runStartedAtMs) => PcmChunker(
             // The format the frames ARRIVED in, never the one asked for. See
             // [CallAudioFrames].
             sampleRate: sampleRate,
             channels: channels,
             firstIndex: firstIndex,
             runStartedAtMs: runStartedAtMs,
           ));

  /// Taps that have not come off. A recording will not start while this has
  /// anything in it.
  ///
  /// Each carries what is still running, when something is: a detach that timed
  /// out has NOT stopped, and asking the same closure again would run a second
  /// stop over the top of the first. The next attempt waits for what is already
  /// in flight instead, and only re-asks a detach that actually threw.
  final List<_UnreleasedTap> _unreleased = [];

  bool get isRecording => _running;

  /// Whether this device was still attached and recording the instant its
  /// MOST RECENT HANGUP-SHAPED stop began (`stop(settleDeliveries: false)`)
  /// -- captured once, inside [_stop], before that stop's own work could
  /// change [_running]. False until such a stop actually does real work.
  ///
  /// This exists because [isRecording] cannot answer "was this device still
  /// carrying the recording when the call ended": [finish] calls [stop] as
  /// its own first act, and by the time finish's own stop has run,
  /// [isRecording] is never true, whatever it was a moment before. Whoever
  /// decides whether to publish [audioRecording]'s half has to read THIS
  /// instead, and has to read it from a point that is guaranteed to run after
  /// the call's own final stop -- see `CallRecord.finish`, which is reached
  /// only after `ActiveCall.hangUp` (which calls [stop] and then
  /// [CallCaptureService.finish]) has already completed.
  ///
  /// SETTLE-SHAPED stops (the default `settleDeliveries: true`) are ignored
  /// here with ONE exception. A mid-call HANDOVER -- a device that lost the
  /// election and is never re-elected -- must not latch this, or it would sit
  /// at a stale `true` forever: nothing else ever runs `_stop`'s real work a
  /// second time to correct it, because the later hangup-shaped stop finds
  /// everything already clean and short-circuits before reaching the write
  /// site. The exception is a PEER-DROP PAUSE (`preserveCarrier: true`): the
  /// recorder stops because the peer or the connection went away while this
  /// device is still the account's SOLE recorder, so it IS still the carrier
  /// and the same short-circuit that protects a handover would otherwise lose
  /// its half. That stop latches `true`; a handover does not. See [_stop]'s
  /// own comment at the write site for the full argument, and
  /// `call_capture_test.dart`'s "wasCarryingBeforeLastStop" and "a peer-drop
  /// pause" groups for the mutation-proven scenarios.
  bool get wasCarryingBeforeLastStop => _wasCarryingBeforeLastStop;
  bool _wasCarryingBeforeLastStop = false;

  /// Whether audio is ACTUALLY reaching this recorder right now.
  ///
  /// Not the same question as [isRecording], and the difference is the whole
  /// reason this exists. [isRecording] says a tap was attached and nothing has
  /// stopped it; a tap that attached and then produced nothing — the failure
  /// the first-frame watchdog exists to catch — answers TRUE to that for the
  /// fifteen seconds it takes the watchdog to fire. This answers true only
  /// while a chunker exists, and a chunker is created by an arriving frame and
  /// let go by the run that ends, so it is a statement about audio rather than
  /// about intent.
  ///
  /// What a sibling is told, and therefore the only thing on which a displaced
  /// device is entitled to throw its own captured audio away. It has to be the
  /// stronger of the two.
  ///
  /// FALSE WHILE MUTED, which falls out rather than being special-cased: a mute
  /// ends the run and lets the chunker go, because a gap in the transcript is
  /// what a mute should be. A muted device is not holding anybody's words.
  bool get capturingAudio => _running && !_stopping && _chunker != null;

  /// Names the uninterrupted stretch of captured audio running now, or null
  /// when none is.
  ///
  /// A TOKEN rather than a flag, because a sibling watching this from across
  /// the SFU sees only the latest value an attribute ever held: attribute
  /// writes are last-write-wins, so a stop and an immediate restart can leave
  /// the watcher reading the same "yes" before and after and never learning
  /// that anything happened in between. The audio in that gap belongs to
  /// nobody, and the number changing is the only evidence of it.
  ///
  /// Counts RUNS, not sessions and not attach attempts. A run is the span
  /// between a first frame and whatever ends it — a stop, a mute, a tap that
  /// died — so a mute in the middle of a stretch shows up here as a break,
  /// which is what it is. A sample-rate change does not: it swaps the chunker
  /// inside one callback with no silence between, so the audio is continuous
  /// and the token must not move.
  String? get captureRun => capturingAudio ? '$_runCount' : null;

  /// How many runs of captured audio this recorder has begun. Never reset
  /// within a call, so a token is never reused.
  int _runCount = 0;

  /// Told that audio has begun arriving, at the first frame of a run.
  ///
  /// Set by whoever owns the election, and the counterpart of [onCaptureLost].
  /// The state is level-triggered and would be picked up by the next election
  /// anyway; this only makes the news PROMPT. That matters because the window
  /// it shortens is the one in which a sibling, displacing this device, cannot
  /// yet see that this device is recording — and delivers a duplicate rather
  /// than deferring to a copy it could not tell was being held.
  void Function()? onCaptureStarted;

  /// Begins recording [track].
  ///
  /// Requests the capture format explicitly rather than accepting whatever the
  /// device happens to produce, so a chunk's bytes mean the same thing on every
  /// platform and the header we write over them is always true.
  Future<void> start(AudioTrack track) async {
    // FIRST, above every guard below. [_stop] clears `_running` early but does
    // not take the chunker until AFTER awaiting the detach, so a start landing
    // inside that window passed every guard, attached a second tap, and fed the
    // OLD chunker — the two runs glued together across the very gap that
    // separates them.
    //
    // Snapshotted, because this method clears the field a few lines down.
    // Awaiting it after that point would await a field it had just cleared and
    // fix nothing.
    final stopping = _stopped;
    if (stopping != null) await stopping;

    if (_running) {
      throw StateError('A call recording is already running');
    }
    if (_detach != null || _unreleased.isNotEmpty) {
      // A previous tap never detached. Retried HERE, before refusing, because
      // this is the moment somebody actually wants to record — and the only
      // other thing that ever comes back to a held tap is a stop, which a
      // device that keeps winning the election never performs. Left to the
      // stop alone, one detach that threw and would have succeeded on the
      // second ask kept this device silent for the rest of the call and, worse,
      // marked it as unable below.
      final before = _session;
      await _releaseUnreleased();
      // That retry is the ONLY yield between the serialisation above and
      // `_running = true`, so it is the one window in which a stop can land and
      // finish unseen — the await at the top of this method has already been
      // and gone. The session is what catches it: [_stop] bumps it
      // synchronously, above every await of its own, and it cannot take the
      // early return that would skip the bump — whichever of the two conditions
      // brought us into this branch is exactly one of the terms in that guard,
      // still true while the retry runs.
      if (_session != before) {
        // A stop ended the stretch this start was for. Attaching now would put
        // a tap on a recording that is already over — and if that was the LAST
        // stop of the call, nothing would ever come back to take it off. The
        // election offers this device the recording again two seconds later,
        // when there is a stretch to attach it to.
        throw StateError('The recording stopped while the tap was coming off');
      }
      if (_detach != null || _unreleased.isNotEmpty) {
        // It survived the retry. That is not a bad moment any more — it is a
        // tap this device cannot let go of, and until it does no new recording
        // may start over the top of it: two taps feeding one chunker would
        // count the learner's own voice twice. Losing this stretch of analytics
        // is recoverable, counting it twice is not.
        //
        // Everything this can see was ASKED, which is what makes it evidence
        // about the device rather than about the timing. The only release that
        // could add a tap here without the session bump above catching it is an
        // overtaken start's, and one of those cannot be in flight while this
        // branch runs: the start that publishes it has to get past this same
        // guard first, so [_unreleased] was empty when it did, and while it
        // holds `_releasing` above zero a later start with an empty
        // [_unreleased] skips this branch entirely and refuses below without
        // blaming anything. Nothing else refills the list in between.
        _canCapture = false;
        throw StateError('The previous audio tap is still attached');
      }
    }
    if (_releasing > 0) {
      // A release that is still DECIDING, which is the case the two collections
      // above both miss: across that span the tap it is working on is in
      // neither of them. The window is real rather than theoretical — a tap
      // arriving after the stop it belonged to is released outside the memoised
      // stop, so nothing above serialises against it.
      //
      // A REFUSAL rather than a wait, deliberately, even though
      // [_releasingWork] publishes that release and could be awaited. A wait
      // here would give a stop the whole length of a detach to land and
      // complete unseen, and this start would then attach over the top of a
      // call that had ended.
      //
      // And [_canCapture] is deliberately NOT touched. This is a millisecond of
      // timing rather than anything true about the device, nothing retries it,
      // and standing a healthy device aside for the rest of a call over a stop
      // that merely landed mid-attach is the failure the distinction exists to
      // prevent.
      throw StateError('The previous audio tap is still coming off');
    }
    if (_tapDeaths >= _tapDeathLimit) {
      // Nothing is attached and nothing is recording afterwards, which is the
      // same answer this gives on a device that has no tap point at all. See
      // [_tapDeathLimit] for why it is an answer rather than a throw.
      return;
    }
    _stopping = false;
    _stopped = null;
    // A discard belongs to the stretch the election decided it for. Carrying it
    // into the next one would silently drop a tail nobody else recorded.
    _discardOnStop = false;
    // The carrier latch belongs to the stretch it was set for, for the same
    // reason. A new stretch re-opens the question of who carries it, so a `true`
    // left by an earlier PEER-DROP PAUSE (see [_stop]) must not survive into it:
    // otherwise a device that paused, resumed, and then handed the NEW stretch
    // to a sibling would still read as the carrier of a half the sibling now
    // owns. Cleared here so only the LAST stop of the last stretch decides.
    _wasCarryingBeforeLastStop = false;
    _running = true;
    final session = ++_session;
    final DetachTap? detach;
    try {
      // The callback closes over the session it was opened FOR. See [_onFrames]
      // for the hole that closes.
      detach = await tap.open(
        track,
        (samples, sampleRate, channels, {droppedMs = 0}) =>
            _onFrames(samples, sampleRate, channels, session, droppedMs),
        // Carries the same session, for the same reason: a tap that dies long
        // after the stretch it belonged to ended must not end the one running
        // now.
        onDead: () => _onTapDied(session),
      );
    } catch (_) {
      // Left clear so a transient failure can be retried by the next election.
      // Recording as started forever would refuse every later attempt.
      //
      // And the run ENDS here rather than leaving whatever the tap already
      // handed over in place for the next run to inherit, glued across the gap.
      // That audio is real: if the tap called us back then the platform was
      // already handing over microphone samples and only the handshake failed,
      // so it is delivered like any other. It is not a refused microphone
      // either — `capture_refused` is whether the PERMISSION was refused, which
      // a failed open cannot answer, so there is no contradiction to avoid.
      //
      // Gated on the session for the same reason `_running` is: a stop that
      // landed first has already ended this run, and a start after it owns
      // whatever chunker exists now.
      if (_session == session) {
        _running = false;
        _endRun();
      }
      rethrow;
    }
    if (_session != session) {
      // A stop landed while this was attaching. The tap belongs to a recording
      // that is already over, so it is released here rather than stored: by the
      // time it arrived another recording may already own [_detach], and writing
      // over that would leave the live tap untracked.
      //
      // Published while it runs, because this is the ONE release that happens
      // outside [_stopped]: the stop that overtook this start has already
      // completed and cleared it. A stop arriving now would otherwise finish
      // its own residue sweep before this release has decided, and whatever
      // this one goes on to hold would be held with nothing left to come back
      // to it. Cleared only if it is still ours — a later overtaken start owns
      // the field once it publishes its own.
      final releasing = _releasingWork = _release(detach);
      try {
        await releasing;
      } finally {
        if (identical(_releasingWork, releasing)) _releasingWork = null;
      }
      return;
    }
    _detach = detach;
    // The platform ANSWERED, about the device rather than about this attempt,
    // and this is the only place that answer is heard. Re-derived rather than
    // latched: a build where the tap point appears late — a processing factory
    // that was still initialising — says so on the attach that finally works,
    // and the election hears it on the next tick.
    _canCapture = detach != null;
    if (detach == null) {
      // No tap on this device. Nothing is recorded, and the call is unaffected.
      _running = false;
      // The run ends here too. It is a no-op when no frames arrived, and that
      // is the reason to make the call rather than to reason about it: the
      // argument that no tap means no chunker rests on a guarantee
      // [CallAudioTap] does not state, and if frames CAN arrive before a throw
      // then nothing says they cannot arrive before a null return.
      _endRun();
    }
  }

  /// Lets go of a tap, and does not lose it if it will not let go.
  ///
  /// The only way a tap is ever released. A detach that throws has left the tap
  /// attached to the track, so it is kept rather than dropped: the next stop
  /// tries it again, and until one succeeds no new recording may start over the
  /// top of it — two taps feeding one chunker would count the learner's own
  /// voice twice.
  ///
  /// Held in a list rather than back in [_detach] because there can genuinely be
  /// more than one: a tap arriving late from an [start] that a stop overtook is
  /// not the tap the current recording owns, and the two must not displace each
  /// other.
  Future<void> _release(DetachTap? detach) async {
    // Counted SYNCHRONOUSLY, above everything, and given back only in the
    // `finally` — so the count covers every branch below, including the clean
    // one that ends up holding nothing. Counting from inside the branches that
    // hold instead would leave exactly the window this exists to close: while a
    // detach is still deciding, the tap is in neither [_detach] nor
    // [_unreleased], and both readers conclude there is nothing attached.
    _releasing++;
    try {
      await _releaseNow(detach);
    } finally {
      _releasing--;
    }
  }

  /// The release itself. Split out only so [_release] can count around all of
  /// it without wrapping every return in a guard.
  Future<void> _releaseNow(DetachTap? detach) async {
    if (detach == null) return;
    // Invoked inside a guard, and through Future.value because a tap may detach
    // synchronously — the renderer's cancel does. It may also THROW
    // synchronously, and called outside a guard that throw escaped this method
    // altogether: the tap was never retained, so nothing ever came back to it
    // and it stayed attached in silence.
    final Future<void> running;
    try {
      running = Future.value(detach());
    } catch (e, s) {
      // It threw before it returned anything at all. Nothing is in flight, and
      // the tap is certainly still attached.
      _hold(_UnreleasedTap(detach, null));
      Logs().w('Could not detach the call audio tap; it stays claimed', e, s);
      return;
    }
    // Read from a flag rather than by catching TimeoutException. The LiveKit
    // package exports its own class of that name, and this file imports it for
    // AudioTrack, so `on TimeoutException` here binds to LiveKit's and silently
    // never matches the one dart:async throws — every timeout took the path
    // meant for a tap that threw, and the tap was asked to detach a second time
    // while the first was still running. Any file in this feature that imports
    // livekit_client has the same trap.
    var stillRunning = false;
    try {
      // Bounded, because teardown waits on this. A platform call that never
      // came back left the hangup unfinished for good: the call was never
      // written and every word of it went uncredited, to protect a tap that
      // was already lost either way.
      await running.timeout(
        detachTimeout,
        onTimeout: () => stillRunning = true,
      );
    } catch (e, s) {
      // It threw, so nothing is running and the tap is certainly still on. This
      // one is worth asking again.
      _hold(_UnreleasedTap(detach, null));
      Logs().w('Could not detach the call audio tap; it stays claimed', e, s);
      return;
    }
    if (stillRunning) {
      // Kept along with what is running, so the next stop waits for THAT rather
      // than starting a second detach over the top of it.
      _hold(_UnreleasedTap(detach, running));
      Logs().w('The call audio tap has not come off yet; it stays claimed');
    }
  }

  /// Holds a tap that has not come off, and lets go of it the moment it does.
  ///
  /// Only a stop ever comes back to these, and a stop happens at the END of a
  /// call — so a tap that timed out and then detached a second later would
  /// otherwise block every recorder election for the rest of the call, and this
  /// device would sit silent through the whole conversation.
  void _hold(_UnreleasedTap tap) {
    _unreleased.add(tap);
    tap.running
        ?.then((_) => _unreleased.removeWhere((held) => identical(held, tap)))
        // An error means it answered too: it is no longer in flight, so it may
        // be asked again, which is what an entry with nothing running means.
        .onError((Object _, StackTrace _) {
          final at = _unreleased.indexWhere((held) => identical(held, tap));
          if (at >= 0) _unreleased[at] = _UnreleasedTap(tap.detach, null);
        });
  }

  /// Tries the taps that would not let go before. Taken and cleared first, so a
  /// failure adds itself back for next time rather than being retried forever
  /// inside this loop.
  Future<void> _releaseUnreleased() async {
    if (_unreleased.isEmpty) return;
    // Counted for the same reason [_release] is, and it has to begin ABOVE the
    // clear below: between taking the list and putting back whatever would not
    // come off, these taps are in no collection at all.
    _releasing++;
    try {
      final pending = List.of(_unreleased);
      _unreleased.clear();
      for (final tap in pending) {
        final running = tap.running;
        if (running == null) {
          // It threw last time; nothing is in flight, so ask again.
          await _release(tap.detach);
          continue;
        }
        var stillRunning = false;
        try {
          // Already running. Waiting is the only safe thing: asking again would
          // stop the platform capture a second time while the first stop is
          // still going.
          await running.timeout(
            detachTimeout,
            onTimeout: () => stillRunning = true,
          );
        } catch (e, s) {
          // It finally answered, with an error. Nothing is running now, so the
          // next stop may ask again.
          _hold(_UnreleasedTap(tap.detach, null));
          Logs().w('The call audio tap refused to come off', e, s);
          continue;
        }
        if (stillRunning) {
          _hold(tap);
          Logs().w('The call audio tap has still not come off');
        }
      }
    } finally {
      _releasing--;
    }
  }

  /// Whether the learner has muted. Frames are dropped while it is set.
  ///
  /// A gate the recorder owns, NOT LiveKit's mute. LiveKit's mute only stops
  /// PUBLISHING to the peer; on Android this tap reads the audio module's
  /// capture output directly, upstream of that, and `stopAudioCaptureOnMute` is
  /// off so the module keeps running — so without this a muted learner would
  /// still be recorded and transcribed. Dropping the frames means a mute is a
  /// gap in the transcript, which is what a mute should be.
  bool _muted = false;

  /// The mute state as of the LAST frame this saw, muted frames included.
  ///
  /// A frame's `droppedMs` is a duration with no timestamp, describing the
  /// interval BEFORE it -- from the previous delivered frame to this one -- and
  /// a mute can flip anywhere INSIDE that interval. Two facts bound it: the mute
  /// state at each end, this field for the previous frame and `_muted` for the
  /// current one. No single flag can place a mid-interval flip, so the drop is
  /// counted UNLESS the interval was muted at BOTH ends; if either end was
  /// unmuted, some of it could hold real speech and it must be counted. That
  /// over-reports at worst a drop that was mostly muted -- a harmless
  /// over-count on the safe side -- and never silently loses speech, which
  /// reading a single end did: the previous frame alone lost a mute-then-unmute
  /// drop, the current frame alone lost an unmute-then-mute one, each published
  /// as `capture_dropped_ms: 0` over a hole in the recording.
  bool _mutedAsOfLastFrame = false;

  /// Gates or ungates capture to match the microphone button.
  ///
  /// The run ends HERE rather than in [_onFrames], and on the false -> true
  /// transition only. After a mute no more frames arrive, so a flush that waits
  /// for one never runs: the words spoken before the mute would sit in the
  /// chunker until the next stop and come out glued to whatever was said after
  /// the learner unmuted. Nothing else happens here — the ordering and the race
  /// are [_endRun]'s problem, solved once.
  void setMuted(bool muted) {
    final wasMuted = _muted;
    _muted = muted;
    if (muted && !wasMuted) _endRun();
  }

  /// Ends the current run, and is the ONE place a run ends.
  ///
  /// Five paths reach it — a stop, a sample-rate change, a mute, a tap that
  /// failed to open, and a start that overtook a stop — and listing those
  /// rather than unifying them is how three of the five came to be missing.
  ///
  /// Takes and clears [_chunker] FIRST, which is what makes it idempotent: two
  /// callers racing across an await cannot flush the same chunker twice.
  ///
  /// Then flushes, and only THEN reads `nextIndex`. That order is easy to get
  /// backwards and costly when it is: `flush()` increments the index through
  /// its own cut, so reading `nextIndex` first hands back the tail's own number
  /// and the sink — which keys results by index — takes the next real chunk for
  /// a redelivery of that tail.
  void _endRun() {
    final chunker = _chunker;
    _chunker = null;
    if (chunker == null) return;

    // Deliberately NOT where the call-audio-recording sink's own run ends.
    // This method is called for a MUTE too (see the five paths above), and a
    // mute must not end that run: it wants a CONTINUOUS file with silence
    // standing in for a mute, where the transcript wants a gap. See
    // [_audioRunFormat] and [_endAudioRun], which fire on exactly the three
    // paths above that ARE an absence of capture for the recording as well
    // -- a stop, a tap that failed to open, and a format change -- and skip
    // the two that are not: a mute, and a start that overtook a stop (which
    // never delivered a frame to begin a run with).

    final tail = chunker.flush();
    // Remembered before the chunker is let go, so a later stretch of the same
    // call numbers on from here.
    _nextIndex = chunker.nextIndex;
    // And so a later stretch cannot claim to have been captured before this
    // one finished. See [_notBeforeMs].
    _notBeforeMs = chunker.endedAtMs;

    // What this run covered, stated HERE because this is where a run's extent
    // is known exactly and where the decision to hand its tail over is taken.
    // Both facts come off the chunker's own single-truncation arithmetic — the
    // same numbers every chunk in the run was stamped from — so the stretch a
    // sibling is asked to cover and the stretch this half claims to hold are
    // measured the way the audio was, not reconstructed afterwards.
    final handingOver = tail != null && _discardOnStop;
    _recordRun(
      from: chunker.runStartedAtMs,
      to: chunker.endedAtMs,
      handedOverFrom: handingOver ? tail.startedAtMs : null,
    );

    if (tail == null) return;
    if (_discardOnStop) {
      // Another of this account's devices was recording the same words at the
      // same time, and delivering these would credit the learner twice for
      // saying them once — the sink keys a result by capture session and chunk
      // index, and two devices are two sessions, so nothing downstream absorbs
      // it. The numbering above still moves: this stretch happened, and a later
      // one that renumbered over it would be taken for a redelivery.
      Logs().i(
        'Dropping call audio chunk ${tail.index}: another device of this '
        'account was recording the same stretch',
      );
      // Told to the sink, not merely logged. A log is gone by the time anybody
      // reads the transcript, and this is the one decision in the capture path
      // that destroys audio on the strength of a claim about ANOTHER device --
      // so the half has to carry the fact that it was made. A sibling's half
      // showing the same stretch is what makes a discard verifiable after the
      // event, and nothing could check it at all while this returned in
      // silence.
      sink.discarded(tail);
      return;
    }
    _hand(tail);
  }

  /// Ends the call-audio-recording sink's own run, if one is open.
  ///
  /// Deliberately NOT called from [_endRun]: that method also ends a run for
  /// a MUTE, and this one must not, because the recording wants a CONTINUOUS
  /// file with silence standing in for a mute rather than a break. Called
  /// instead from the specific places that ARE an absence of capture for the
  /// recording too -- a stop actually doing its work, and a format change
  /// detected in [_onFrames] -- so [_audioRunFormat] and [_endRun]'s own
  /// [_chunker] can legitimately disagree about whether a run is open right
  /// now (muted) while never disagreeing about when one truly ends.
  ///
  /// Idempotent: a no-op when [_audioRunFormat] is already null, so calling
  /// this from more than one path that might both apply to the same instant
  /// costs nothing.
  void _endAudioRun() {
    if (_audioRunFormat == null) return;
    _audioRunFormat = null;
    final recordingSink = audioRecording;
    if (recordingSink == null) return;
    try {
      recordingSink.onRunEnded();
    } catch (e, s) {
      Logs().w('The call audio recording sink failed to end a run', e, s);
    }
  }

  /// Where a run that begins after an ABSENCE of capture sits, in absolute Unix
  /// milliseconds.
  ///
  /// The wall clock is read exactly ONCE per call, at the first run, and every
  /// gap after that is measured from a monotonic counter started at the same
  /// instant. A wall clock is not for measuring an elapsed interval; that is
  /// what a monotonic clock is for, and reading one per run made every device
  /// clock correction during a call a fabricated gap.
  ///
  /// An earlier version bounded that with a floor on the previous run's end and
  /// called it done. The floor only ever caught a BACKWARD step. A clock nudged
  /// FORWARD between runs — after a mute, a stop and resume, or a tap that
  /// failed to open — stamped the next run arbitrarily late, and the render
  /// gate accepted it, because a position invented an hour into the future is
  /// still non-null and still non-decreasing. Bounding one direction and
  /// leaving the other open is the tell that the mechanism was wrong rather
  /// than the bound.
  ///
  /// The read is taken when the chunker is built, which is inside the first
  /// callback of the run — by which time that batch's audio has already been
  /// captured. So the batch's own duration comes off, which is exact and free:
  /// the samples are in hand and their length is the answer.
  ///
  /// What remains is the platform's own latency between a microphone sample and
  /// the callback that carries it. It is not measurable from here, it is small,
  /// and it is very nearly the same on both devices — the same app, the same
  /// tap — so it largely cancels in the comparison that matters.
  ///
  /// [_notBeforeMs] stays, as defence rather than as the mechanism, for every
  /// run AFTER the first. A monotonic counter that stalls — some platforms hold
  /// one still while the device sleeps — makes a later run's reading land back
  /// near an earlier one, and the floor pins it AFTER the previous run's end
  /// rather than in front of it. Compressed and ordered is the failure this
  /// design accepts there; scattered is not.
  ///
  /// The FIRST run has no such floor — [_notBeforeMs] is zero until a run closes
  /// — and that is where a stalled counter SCATTERS rather than compresses. A
  /// device that begins the call MUTED latches the base at t0 on its first
  /// (muted) frame but opens no transcript run until it unmutes; if it sleeps
  /// through the mute with the counter held still, the unmuted run is measured
  /// from a counter that missed the whole sleep and regresses to ~t0 — and a
  /// turn spoken minutes in then sorts ahead of the peer's earlier speech ("my
  /// bye came first"). So while no run has closed, a WALL-elapsed lower bound
  /// stands in for the missing floor. A wall clock is not for measuring an
  /// interval and can be corrected out from under a call — which is why every
  /// run's POSITION still comes off the monotonic counter — but across the first
  /// run it is the one reading that survives the counter freezing, and a run
  /// cannot have begun before the wall says the call itself did.
  ///
  /// The wall floor is confined to that first run ON PURPOSE. Once a run closes,
  /// [_notBeforeMs] takes over and the wall is not read again, so a wall clock
  /// STEPPING mid-call — the hazard the monotonic counter exists to survive —
  /// moves nothing, exactly as before.
  ///
  /// This closes the reported bug and every muted-start sleep where the wall
  /// clock keeps honest time through a monotonic stall — the common, high-harm
  /// case, where the turn otherwise sorts to the very front. It is a TRADE, not
  /// a free win: with only two local clocks and no third reference, a stalled
  /// monotonic (wall sane) is indistinguishable from a wall that itself jumped,
  /// so the wall floor is trusted in cases where it is wrong. The full set of
  /// clock-failure residuals — all fixable only by a suspension-inclusive
  /// platform clock (iOS CLOCK_BOOTTIME / Android elapsedRealtime), which does
  /// not exist in this app and is deferred:
  ///   (1) Later runs: a device that sleeps during a mute AFTER it has already
  ///       spoken compresses the post-sleep run toward its own earlier speech
  ///       rather than recovering the true gap (ordered, not scattered).
  ///   (2) First run, wall steps FORWARD during the muted window: the wall floor
  ///       is inflated and the run is placed too LATE. Pre-fix ignored the wall
  ///       and placed it correctly here, so this case is newly WORSENED by the
  ///       floor — accepted because a late-placed turn is far less jarring than
  ///       the front-scatter the floor removes, and a forward wall jump mid-call
  ///       is rare.
  ///   (3) First run, wall steps BACKWARD by more than the separation from the
  ///       peer's earlier turn during the sleep: both the monotonic position and
  ///       the wall floor sit near t0 and the late first run can still scatter
  ///       ahead of that earlier speech.
  /// The trade is deliberate: it removes the common front-scatter at the cost of
  /// rarer, lower-harm wall-anomaly misplacements, and the exact fix for the
  /// whole class is the deferred platform clock.
  int _runStartsAt(int samples, int sampleRate, int channels) {
    var base = _baseUnixMs;
    if (base == null) {
      base = _baseUnixMs = nowMs();
      _elapsedAtBase = elapsedMs();
    }
    // Interleaved samples divided by the channel count the frames actually
    // carry. Dividing by the count we REQUESTED puts this out by exactly that
    // factor, which moves where the run -- and every turn in it -- is placed.
    final batchMs = (samples ~/ channels) * 1000 ~/ sampleRate;
    final startedAt = base + (elapsedMs() - _elapsedAtBase) - batchMs;
    // The lower bound the position may not fall below. Before any run has closed
    // [_notBeforeMs] is zero and cannot stop a stalled counter regressing the
    // first run to ~base, so the wall-elapsed position stands in for it; after a
    // run closes [_notBeforeMs] is the floor and the wall is left unread, so a
    // forward wall step cannot move a later run.
    final floor = _notBeforeMs == 0
        ? base + (nowMs() - base) - batchMs
        : _notBeforeMs;
    return startedAt > floor ? startedAt : floor;
  }

  /// The wall clock at the moment this call's first run began, and the reading
  /// of the monotonic counter taken at that same instant. Null until then.
  ///
  /// Per call, because a [CallCaptureService] is built per call session. Every
  /// position this device produces for the call is this one number plus a
  /// monotonic offset, so a clock correction mid-call moves nothing at all --
  /// once a run has closed. Before that, [_runStartsAt] additionally floors the
  /// first run by wall-elapsed, the one case a clock correction can still move a
  /// position (see there for why the first run has no other floor to lean on).
  int? _baseUnixMs;
  int _elapsedAtBase = 0;

  /// Takes audio from the tap.
  ///
  /// The chunker is built here rather than at start, because the rate is not
  /// known until audio arrives — and it can change mid-call when the device or
  /// the negotiated codec does. A change ends the current chunk rather than
  /// reinterpreting samples already collected at the old rate, which would
  /// stretch or compress what the learner said.
  void _onFrames(
    Int16List samples,
    int sampleRate,
    int channels,
    int session,
    int droppedMs,
  ) {
    // Whether this frame's SAMPLES belong to the stretch running now.
    //
    // Gated on the SESSION, not on [_running] alone. When `tap.open` throws
    // there is no detach handle, so a tap installed before the throw cannot be
    // tracked in [_unreleased] and never comes off — and the next start sets
    // `_running` before ITS own open, so the leaked tap's frames were accepted
    // straight into the run that followed. Ending the run does not help there,
    // because that audio arrives afterwards. A callback that carries the
    // session it was opened for can only ever feed that one, which closes a
    // hole that predates the positions below.
    // The narrower of two questions this callback asks about the same frame.
    // [recorderLive] is "is there a stretch running at all" -- live, not
    // stopping, not a stale session -- and it is ALSO what the call-audio-
    // recording sink below is fed on, mute included. [forThisRun] narrows
    // that once more, by mute, for the transcript chunker alone: a mute is a
    // gap in the transcript, but not a gap in a continuous recording (see the
    // fan-out below), so the two consumers of this tap part ways on exactly
    // that one term.
    final recorderLive = session == _session && _running && !_stopping;
    final forThisRun = recorderLive && !_muted;

    // Counted ABOVE that gate, because a report that audio was lost is not the
    // audio. Every reason the samples are refused below — a hangup already
    // unwinding, a leaked tap, a stretch that has ended — is a reason not to
    // RECORD post-stop microphone audio, and none of them is a reason to forget
    // that a stretch we WERE recording had a hole in it.
    //
    // That distinction is the whole of the bug this closes. The tap reports a
    // drop on the frame AFTER it, so the drop at the end of a call rides out on
    // the tail the platform hands over as it detaches — which arrives once
    // `_stopping` is set. Counted only inside the accepted path, that number was
    // read, dropped on the floor, and the half published `capture_dropped_ms: 0`
    // over a hole in the recording: the exact silent-completeness failure the
    // field exists to prevent.
    //
    // A MUTED span is the one exclusion, and it is not a hole. Frames arriving
    // while muted are dropped by us on purpose — a mute is a gap in the
    // transcript, which is what a mute should be — so audio the platform lost
    // inside that span is audio this device was refusing anyway. Counting it
    // would report a failure for a stretch nobody was ever going to record, on
    // every call where somebody muted, and leave the flag meaning nothing when
    // it matters.
    //
    // But the mute state that decides this is the one during the DROPPED
    // interval, not this frame's, and a mute can flip anywhere inside it. The
    // interval runs from the previous delivered frame ([_mutedAsOfLastFrame]) to
    // this one (`_muted`), and a duration with no timestamp cannot say where in
    // between a flip fell — so the only safe reading is to skip the drop ONLY
    // when the interval was muted at BOTH ends. If either end was unmuted, some
    // of it could be real speech and it is counted. Reading a single end lost
    // one direction each: the current end alone dropped an UNMUTED-then-muted
    // report, the previous end alone dropped a muted-then-UNMUTED one — both
    // published as `capture_dropped_ms: 0` over a hole. This over-counts at worst
    // a mostly-muted drop, which is the safe way to be wrong.
    if (droppedMs > 0 && !(_mutedAsOfLastFrame && _muted)) {
      _captureDroppedMs += droppedMs;
    }
    // Advanced for EVERY frame, muted ones included, and BEFORE the gate below
    // can return: it is this frame's mute state that governs the NEXT frame's
    // dropped interval, whether or not this frame's own samples are recorded.
    _mutedAsOfLastFrame = _muted;

    // Fed to the call-audio-recording sink whenever this run is LIVE, mute
    // included -- ahead of the `!forThisRun` return below, because a muted
    // frame is exactly the case that return exists to skip for the
    // TRANSCRIPT chunker and NOT the case this second consumer wants skipped.
    // The samples themselves are replaced with silence while muted: the
    // outbound track this device publishes goes silent under a mute already,
    // and doing the same here makes a recording made by the OTHER tap
    // implementation -- the one platform where the raw capture does not
    // reflect the mute (see [PostEchoCancellationTap]) -- agree with it
    // rather than leaking the muted learner's real words into a file meant to
    // hold only what they actually sent.
    //
    // Never fed after a stop, a stale session, or a leaked tap's late frame:
    // [recorderLive] excludes all three, on the same terms [forThisRun]
    // already does for the transcript path, so the two consumers of this tap
    // agree on where a run's audio begins and ends. A second consumer's own
    // failure is caught here and logged rather than allowed to reach the
    // transcript path below it in this same callback.
    if (recorderLive) {
      final recordingSink = audioRecording;
      if (recordingSink != null) {
        // The recording's OWN run boundary -- tracked in [_audioRunFormat],
        // never in [_chunker] -- because [_chunker] does not exist while
        // muted, and a call whose very first frame (or first several) arrive
        // muted must still open a generation and record silence from that
        // first millisecond, not from whenever the learner first unmutes.
        // See [_audioRunFormat]'s own docs for the full argument.
        //
        // Detected and fired BEFORE [onFrame] below, never after: a
        // generation has to exist before this frame can be appended to it. An
        // earlier ordering fed the frame first and only opened the run
        // afterwards (tied to the transcript chunker's own creation, further
        // down), which silently dropped the FIRST frame of every run, muted
        // or not, and additionally never opened anything at all for a
        // muted-from-the-start call.
        final currentFormat = (sampleRate: sampleRate, channels: channels);
        if (_audioRunFormat != currentFormat) {
          // A format change ends the OLD run before this one begins -- a WAV
          // file is one fixed format for its whole length. A no-op when no
          // run was open yet (the ordinary first-frame case).
          _endAudioRun();
          try {
            recordingSink.onRunStarted(
              // The SAME conversion the transcript chunker uses for its own
              // `runStartedAtMs` (see [_runStartsAt]), called here directly
              // rather than borrowed from a chunker that may not exist yet
              // while muted. Safe to call more than once per callback: the
              // underlying wall-clock/monotonic base latches once, on
              // whichever call reaches it first, and every call after that --
              // this one, or the transcript chunker's own later on an
              // unmuted frame -- computes its own correct position from that
              // one shared base.
              _runStartsAt(samples.length, sampleRate, channels),
              sampleRate,
              channels,
            );
            // Latched ONLY after the run actually opened. Set BEFORE the call, a
            // throw inside onRunStarted (a sink that could not mint a
            // generation, as the dart2js `1 << 32` id overflow did) left the
            // format marked open over a generation that never got created -- so
            // every later same-format frame skipped this block, the run never
            // retried, and the recorder stayed dead for the rest of the call
            // after one swallowed warning. Unset-on-failure lets the next frame
            // try again.
            _audioRunFormat = currentFormat;
            _runStartFailed = false;
          } catch (e, s) {
            if (!_runStartFailed) {
              _runStartFailed = true;
              Logs().w(
                'The call audio recording sink failed to start a run; retrying '
                'on the next frame',
                e,
                s,
              );
            }
          }
        }
        try {
          recordingSink.onFrame(_muted ? Int16List(samples.length) : samples);
        } catch (e, s) {
          Logs().w(
            'The call audio recording sink failed on a frame; dropping it '
            'rather than disturbing the transcript',
            e,
            s,
          );
        }
      }
    }

    if (!forThisRun) return;

    // The chunker's side of the same gap, and only for the run that is live.
    // The total above says how much went; this says WHERE, by cutting so no
    // chunk spans it.
    //
    // The gap is given to the chunker only when there IS one to give it to. A
    // run that has not started yet is placed from the clock at its first frame
    // -- a reading already taken after the gap -- so telling a chunker built
    // here about audio dropped before it existed would move the run later than
    // the speech it holds. The total counts it either way: it is lost audio
    // whether or not a run was open to lose it from.
    if (droppedMs > 0) {
      final cut = _chunker?.skip(droppedMs);
      if (cut != null) _hand(cut);
    }

    // Whether this frame is the one that STARTS a run, which is exactly whether
    // there was no chunker to put it in. A sample-rate change further down ends
    // the run and opens another inside this one callback, with no yield
    // between, so nothing outside ever saw it stop and it is not a new run to
    // report — and it does not move this flag either way, because a chunker
    // existed when the frame arrived.
    final firstFrameOfRun = _chunker == null;

    // Audio arrived, so this device's tap point works. That is the one fact
    // that makes a later attach worth attempting again, and it is why
    // [_tapDeaths] counts consecutive failures rather than a call's total.
    if (_tapDeaths != 0) _tapDeaths = 0;

    final held = _chunker;
    // EITHER half of the format changing ends the run, for one reason: samples
    // already collected cannot be reinterpreted in a format they were not
    // captured in. Re-reading mono audio as stereo halves its frame count and
    // stretches it, exactly as re-reading its rate would.
    if (held != null &&
        (held.sampleRate != sampleRate || held.channels != channels)) {
      // A format change is NOT a gap. A sample-rate change happens inside ONE
      // callback and the very same batch continues into the new chunker, so
      // there is no silence between them — only a boundary we imposed. Reading
      // the clock here would invent a gap and push the first new-rate chunk
      // later than the speech actually was, so the new run continues at the old
      // one's end exactly. The three boundaries that ARE an absence of capture
      // — a stop, a mute, a tap that failed to open — go through [_runStartsAt]
      // instead.
      _endRun();
      _chunker = _newChunker(_nextIndex, sampleRate, channels, _notBeforeMs);
    }

    final chunker = _chunker ??= _newChunker(
      _nextIndex,
      sampleRate,
      channels,
      _runStartsAt(samples.length, sampleRate, channels),
    );

    // The call-audio-recording sink's own run boundary is handled entirely
    // above, ahead of the `!forThisRun` return -- see [_audioRunFormat] and
    // the block that opens with `if (recorderLive)`. It is deliberately NOT
    // re-derived here from [held]/[chunker]: that pairing is mute-gated (this
    // line is never reached while muted) and so cannot be the recording's own
    // run boundary, which must not break on a mute.

    for (final chunk in chunker.add(samples)) {
      _hand(chunk);
    }
    if (firstFrameOfRun) {
      // Moved BEFORE the callback, so a listener that reads [captureRun]
      // straight out of this call sees the run it is being told about rather
      // than the previous one.
      _runCount++;
      onCaptureStarted?.call();
    }
  }

  void _hand(PcmChunk chunk) {
    late final Future<void> delivery;
    delivery = _deliver(chunk).whenComplete(() => _inFlight.remove(delivery));
    _inFlight.add(delivery);
  }

  /// Delivers a chunk, retrying a failure rather than dropping it.
  ///
  /// One request lost on a weak connection — ordinary on mobile — used to cost
  /// up to ninety seconds of a learner's speech silently, and it fell hardest on
  /// exactly the people with the worst connections. And the loss was not one
  /// request: a transient burst of 429s or 5xx from an overloaded backend burned
  /// a fixed three attempts in about three seconds and could not outlast the
  /// upload gate's fifteen-second open window, so a blip that had passed by the
  /// time the breaker closed still lost the whole half, device-wide.
  ///
  /// So the retries are EXPONENTIAL and JITTERED (see [_backoffFor]) rather than
  /// a fixed few, and the sequence is bounded by TIME rather than by a count:
  /// it keeps trying, backing off, for as long as [_deliveryRetryBudget] — the
  /// call's own finish window — leaves room for another whole attempt. That
  /// spans the breaker's open window many times over and gives a recovering
  /// backend time to answer, without hammering it and without ever running past
  /// the end of the call: a chunk that genuinely cannot send still falls out of
  /// the loop and is reported lost, exactly as before.
  ///
  /// Never throws. A chunk that cannot be delivered costs its share of the
  /// transcript; it must not take the call down with it.
  Future<void> _deliver(PcmChunk chunk) async {
    final budgetMs = _deliveryRetryBudget.inMilliseconds;
    // The absolute instant, on the injected monotonic clock, past which no
    // further attempt may START. Fixed ONCE, so the check that guards the next
    // attempt is against a deadline rather than against an elapsed total the
    // wait is trusted to have grown by exactly its backoff — [Future.delayed]
    // promises no such thing, and a backoff that resumes late (a busy loop, a GC
    // pause) must not be able to slip an attempt out beyond the window.
    final deadlineMs = elapsedMs() + budgetMs;
    // The room one whole attempt needs before that deadline. An attempt is
    // bounded by [deliveryTimeout], and the reserve ROUNDS UP to the whole
    // millisecond the clock counts in, so a sub-millisecond timeout truncated
    // away cannot leave the last attempt straddling the deadline.
    final attemptCeilingMs = (deliveryTimeout.inMicroseconds + 999) ~/ 1000;
    for (var attempt = 0; ; attempt++) {
      // Teardown cancels an outstanding retry. Once [finish] has stopped waiting
      // for chunks in flight, the sink is closing and another attempt would
      // deliver against it after the call is already gone. This is the ONE line
      // every attempt passes through immediately before it — no await sits
      // between the check and the deliver — so a single check here is enough to
      // guarantee no delivery starts after teardown, whether the loop was
      // mid-backoff or between a failed attempt and its wait when the signal
      // landed. A second check after the attempt or after the backoff would be
      // redundant with this one and could not be told apart from it under test.
      // See [cancelOutstandingDeliveries].
      if (_deliveriesCancelled) break;
      try {
        await sink.deliver(chunk, within: deliveryTimeout);
        return;
      } catch (e, s) {
        Logs().w(
          'Call audio chunk ${chunk.index} delivery attempt '
          '${attempt + 1} failed',
          e,
          s,
        );
      }
      final backoffMs = _backoffFor(attempt).inMilliseconds;
      // No room for this backoff AND one more whole attempt before the deadline:
      // stop now rather than begin a wait whose attempt could not finish in time.
      // Measured against the SAME clock the wait moves, so the budget holds
      // whether time really passes (production) or a test advances it.
      if (elapsedMs() + backoffMs + attemptCeilingMs > deadlineMs) break;
      await _delay(Duration(milliseconds: backoffMs));
      // RE-checked after the wait, before looping back to deliver. This is the
      // half the pre-delay reserve cannot cover: a deadline reserved before a
      // wait is no promise once the wait has resumed late. If the room for a
      // whole attempt is gone, the chunk is lost rather than delivered out of the
      // finish window. Cancellation needs no check here: the loop head catches it
      // before the next deliver.
      if (elapsedMs() + attemptCeilingMs > deadlineMs) break;
    }
    Logs().e(
      'Gave up delivering call audio chunk ${chunk.index}; its words are lost',
    );
  }

  /// The backoff before retry number [attempt] (zero-based: 0 is the wait that
  /// precedes the SECOND delivery attempt).
  ///
  /// Exponential from [_deliveryBackoffBase], doubling each time and capped at
  /// [_deliveryBackoffCeiling], with up to [_deliveryBackoffJitter] of that
  /// added on top so a fleet that all failed on one backend blip does not retry
  /// in lockstep.
  Duration _backoffFor(int attempt) {
    final baseMs = _deliveryBackoffBase.inMilliseconds;
    final ceilMs = _deliveryBackoffCeiling.inMilliseconds;
    // Doubled by a shift only while it can still matter. Once the value has
    // reached the ceiling the shift is skipped — which also keeps this clear of
    // dart2js's 32-bit bitwise overflow (the `1 << 32` trap this file already
    // carries a scar from at the recording sink's generation ids).
    var ms = ceilMs;
    if (attempt < 5) {
      final doubled = baseMs << attempt;
      if (doubled < ceilMs) ms = doubled;
    }
    final jitterMs = (ms * _deliveryBackoffJitter * _jitter()).round();
    return Duration(milliseconds: ms + jitterMs);
  }

  /// Stops recording, flushes the tail, and waits for delivery to settle.
  ///
  /// Idempotent, because a hangup and a disconnect can both land: the tap is
  /// cancelled and the chunker cleared before anything is awaited, so a second
  /// call has nothing left to flush and cannot emit a duplicate tail.
  /// The stop in flight, so two callers join one rather than both running it.
  /// A hangup and a disconnect routinely arrive together, and a check followed
  /// by an await lets both past.
  Future<void>? _stopped;

  /// Ends this stretch of recording.
  ///
  /// [settleDeliveries] waits, briefly, for chunks already handed to the sink.
  /// Teardown passes false: the transcripts go to choreo, and a call is over
  /// when the microphone and the membership are released, never when a
  /// transcription answers. Waiting here held the account's one call open for
  /// as long as choreo took -- which refused the next call and, worse, silently
  /// swallowed an INCOMING ring, because a ring that arrives while this account
  /// reads as busy is dropped from the stream and never replayed.
  ///
  /// Nothing is abandoned by skipping it: [finish] awaits the very same futures
  /// straight afterwards with a far longer bound, and every delivery keeps its
  /// own retry path regardless.
  ///
  /// Only the LOCAL stop is shared between callers. Two of them may want
  /// different settling -- a recorder handover wants it, a hangup does not --
  /// and a memoised whole would have made the second caller inherit the first's
  /// choice, which is how a hangup came to wait out a handover's drain.
  ///
  /// [preserveCarrier] is only ever true on a settle-shaped stop, and says this
  /// stop is a PEER-DROP PAUSE rather than a sibling handover: recording is
  /// stopping because the peer (or this device's own connection) is gone while
  /// this device remains the account's sole recorder, so its carrier status is
  /// latched here rather than lost. A handover leaves it false. It is inert on a
  /// hangup-shaped stop, which reads `_running` directly.
  Future<void> stop({
    bool settleDeliveries = true,
    bool preserveCarrier = false,
  }) async {
    await (_stopped ??=
        _stop(
          settleDeliveries: settleDeliveries,
          preserveCarrier: preserveCarrier,
        ).whenComplete(() {
          _stopped = null;
        }));
    if (settleDeliveries) await _settle(_settleDeliveriesWithin);
  }

  /// Waits for what has already been handed to the sink, bounded.
  ///
  /// The bound applies to the WAITING, never to the audio: each delivery keeps
  /// its own retry path, and nothing here truncates or drops a chunk.
  Future<void> _settle(Duration within) async {
    try {
      await Future.wait(List.of(_inFlight)).timeout(within);
    } catch (e, s) {
      Logs().w('Chunks were still on their way when recording settled', e, s);
    }
  }

  Future<void> _stop({
    required bool settleDeliveries,
    bool preserveCarrier = false,
  }) async {
    // Checked against the taps as well as the chunker: a call can be attached
    // with no chunker yet, because the chunker is not built until audio actually
    // arrives, and returning early there would leave the tap attached. A tap
    // that would not let go counts too — this is the only thing that ever comes
    // back to one, so returning above it would strand it for good.
    //
    // And a release still deciding counts for the same reason, one step
    // earlier: the tap it is working on is not in [_detach] or [_unreleased]
    // YET, but it may be a moment from now. Concluding "everything is off" over
    // the top of one meant the tap it went on to hold was held AFTER the last
    // stop of the call, with nothing left that ever comes back to it — and the
    // next start refuses for the rest of the call.
    if (!_running &&
        _chunker == null &&
        _detach == null &&
        _unreleased.isEmpty &&
        _releasing == 0) {
      return;
    }
    // Captured HERE, before anything below can change [_running] -- see
    // [wasCarryingBeforeLastStop]. A HANGUP-shaped stop (`settleDeliveries:
    // false`; see [stop]'s own docs: a handover wants to settle, a hangup does
    // not) reads `_running` directly. A settle-shaped stop writes it in exactly
    // ONE case, handled by the branch below: a peer-drop PAUSE, where this
    // device is still the sole carrier and the hangup that follows would
    // otherwise short-circuit before it could record that.
    //
    // A mid-call HANDOVER reaching this far means the device WAS carrying,
    // but is being asked to stand aside for a sibling -- the opposite of
    // "still carrying when the call ended" -- and if it is never re-elected,
    // NOTHING ELSE ever runs this line again: a later hangup-shaped stop
    // finds everything already clean and hits the early return above,
    // without reaching this line at all. Recording the handover's `true`
    // here would leave that stale reading standing forever, which is exactly
    // the bug a cold review caught: a device that lost the election minutes
    // before hangup still reported itself as the carrier at the end.
    //
    // A REDUNDANT hangup-shaped stop -- `finish()` calls `stop()` once more
    // after `ActiveCall.hangUp`'s own explicit one has already run -- is safe
    // to skip too, but for the opposite reason: by then everything is already
    // clean, so it hits the SAME early return above and never reaches this
    // line either. Only the FIRST call that actually does real work, with
    // `settleDeliveries: false`, ever writes here -- which is exactly the
    // hangup's own stop, whatever it finds `_running` to be at that instant.
    if (!settleDeliveries) {
      _wasCarryingBeforeLastStop = _running;
    } else if (preserveCarrier && _running && !_discardOnStop) {
      // A PEER-DROP PAUSE, not a sibling handover -- and the one settle-shaped
      // stop that MUST latch the carrier fact. This device stopped recording
      // only because the PEER left (or this device's own connection dropped)
      // with NO sibling taking the stretch over, so it is still the sole
      // carrier of its own outbound half and has to publish it at the eventual
      // hangup. That hangup-shaped stop runs later, finds recording already
      // stopped here, hits the early-return above, and so can never observe
      // that this device was carrying -- exactly the ordering that dropped the
      // non-initiator's half. Recording it HERE is what survives to the read.
      //
      // A genuine sibling HANDOVER is the opposite and is left untouched: it
      // passes `preserveCarrier: false` (see [ActiveCall._reconcile]), the
      // sibling holds the stretch and publishes it, and this device must not
      // claim the same half. `!_discardOnStop` is belt-and-braces on the same
      // distinction -- a stretch handed to a sibling is discarded, never a
      // pause -- so the capture service's own invariant holds whatever the
      // caller passes. [start] clears this latch for each new stretch, so a
      // pause that later resumes and IS handed over cannot leave a stale true.
      _wasCarryingBeforeLastStop = true;
    }
    _session++;

    // Stop taking frames NOW, before the detach, not after it. Detaching a tap
    // is a platform round-trip that can take its bounded seconds to answer, and
    // every frame that arrived while it ran used to be chunked — which after a
    // hangup is post-hangup microphone audio, the learner's private
    // conversation once they believed the call was over. That is the one place
    // this feature must never leak, so frames are refused here first. The cost
    // is at most the tap's last un-flushed batch; everything the learner said up
    // to this line is already in the chunker and is flushed below.
    _stopping = true;
    _running = false;
    // The recording's own run ends HERE too -- no more frames are coming for
    // this stretch, on the same terms the comment above just argued for the
    // transcript's. See [_endAudioRun] for why this is not folded into
    // [_endRun] itself.
    _endAudioRun();

    // Taken and cleared BEFORE it is awaited. Leaving it set across the await
    // let a second stop past the guard above and detach the same tap twice.
    final detach = _detach;
    _detach = null;
    await _release(detach);
    // Then the one release that is not ours: a tap from a start this stop
    // overtook is let go outside [_stopped], so waiting here is what puts
    // whatever it holds in front of the sweep below rather than behind it.
    await _releasingWork;
    // And another go at anything that would not let go earlier. A tap detaches
    // on the next stop or not at all; nothing else ever comes back to it.
    await _releaseUnreleased();

    _endRun();
  }

  /// Takes the news that a tap which attached is never going to deliver.
  ///
  /// The platform side is already gone or was never really there, so this ends
  /// the stretch through the ordinary [stop] — the tap still has to come off,
  /// and the one release path is what does that.
  ///
  /// Gated on the session, so a report from a tap that outlived its own stretch
  /// cannot end the one running now. Gated on [_running] as well, because a
  /// death arriving while a stop is already unwinding is news about a recording
  /// that is over.
  void _onTapDied(int session) {
    if (_session != session || !_running) return;
    // Counted BEFORE the stop and the report below, because both of them can
    // reach [start] again — the report synchronously — and the count is what
    // that start reads.
    _tapDeaths++;
    if (_tapDeaths >= _tapDeathLimit) {
      Logs().e(
        'The call audio tap attached and delivered nothing $_tapDeaths times '
        'on this device; it will not be attached again during this call',
      );
    } else {
      Logs().w('The call audio tap died mid-recording; ending this stretch');
    }
    unawaited(stop());
    // AFTER the stop, which sets the gate and the in-flight stop synchronously
    // before it awaits anything. That is what a listener restarting from
    // straight inside this call needs: the start it makes finds a stop to wait
    // for rather than a race to win, and does not bounce off the "already
    // running" guard. The listener wired today happens to hop a microtask
    // first, so it would survive either order — the ordering is a contract this
    // offers every listener, not something the current one leans on, and it is
    // pinned by a test that restarts synchronously.
    //
    // A stop this side performed by itself is invisible to the owner of the
    // election otherwise: its own record of "I am recording" is written only
    // where IT made the change, so the death would be detected here and then
    // swallowed one layer up — the device would go on winning every election
    // and recording nothing for the rest of the call.
    onCaptureLost?.call();
  }

  /// Stops every outstanding delivery retry, because the call is tearing down.
  ///
  /// Called by [finish] the instant it has stopped waiting for chunks still in
  /// flight: from there the sink is closing and a retry loop still going would
  /// fire a delivery against it after the call is already gone. Finish's wait is
  /// bounded by [Future.timeout], which gives up on its source without cancelling
  /// it, so this -- not the timeout -- is what actually ends the loops. A chunk
  /// still unsent when this lands is lost, honestly, exactly as one the retry
  /// window ran out on. See [_deliver], which reads the flag before each attempt
  /// and after each backoff.
  ///
  /// Visible for testing so the retry loop's response to teardown can be
  /// exercised deterministically through the injected delay seam, rather than by
  /// waiting out finish's real settle window in wall time.
  @visibleForTesting
  void cancelOutstandingDeliveries() => _deliveriesCancelled = true;

  /// Ends the call's recording for good.
  ///
  /// Separate from [stop], which ends one stretch of it. Recording moves between
  /// a learner's devices during a call and comes back, so a stretch ending is
  /// not the audio ending — and telling the sink otherwise, while chunks
  /// numbered on from there were still to come, was a promise this could not
  /// keep.
  Future<void> finish() =>
      _finishing ??= _finish().whenComplete(() => _finishing = null);

  /// The finish in flight, so two callers join one. Cleared on completion, so a
  /// close that failed can still be retried.
  Future<void>? _finishing;

  Future<void> _finish() async {
    // Without settling: this is the one caller that is ABOUT to settle, with a
    // far longer bound. Letting stop settle first would serve a ten second wait
    // and then a two minute one back to back, for the same futures, delaying
    // the transcripts and the analytics credited from them for no reason.
    await stop(settleDeliveries: false);
    if (_finished) return;
    // Everything still on its way — but BOUNDED, like every other wait in a
    // call's life. The bound applies to the WAITING, never to the audio: each
    // delivery keeps its own retry path, and nothing here truncates a chunk.
    // Each delivery's whole retry sequence is itself bounded by
    // [_deliveryRetryBudget], which IS this same window measured from when the
    // chunk was handed over — never later than this stop's own final flush — so
    // a chunk's retries always finish inside this wait rather than outliving it.
    // This outer bound is the backstop for a delivery that overruns even that,
    // and when it fires the record is still written with what landed, because a
    // record slightly short is strictly better than one that never appears. The
    // chunks still outstanding are logged as lost.
    try {
      await Future.wait(List.of(_inFlight)).timeout(finishSettleWithin);
    } catch (e, s) {
      Logs().w(
        'A call audio chunk never landed before the finish gave up',
        e,
        s,
      );
    }
    // Finish has now stopped waiting for what was in flight. A bounded wait does
    // NOT stop the loops it stopped waiting on -- [Future.timeout] gives up on
    // its source, it does not cancel it -- so a delivery still backing off would
    // keep firing against the sink about to close below. Cancel them here: a
    // chunk still unsent is lost, honestly, like any the window ran out on.
    cancelOutstandingDeliveries();
    // Marked only once it has actually happened. Marking first meant a close
    // that failed was remembered as done, and the retry that could have fixed
    // it skipped the work — the same mistake as clearing a handle before the
    // operation it stands for has succeeded.
    _drainComplete = await sink.close();
    _finished = true;
  }

  bool _finished = false;

  /// Whether the sink settled everything it still had in flight.
  ///
  /// FALSE means work was abandoned, so whatever the sink holds is knowingly
  /// short of what was said. Carried out to whoever publishes the transcript,
  /// because a half that quietly claims to be everything somebody said is the
  /// one thing this feature must not produce. Optimistic until [finish] runs:
  /// nothing has been abandoned before then.
  bool get drainComplete => _drainComplete;
  bool _drainComplete = true;

  /// The frame's samples as 16-bit PCM. Lives with the tap that produces them.
  @visibleForTesting
  static Int16List pcmOf(AudioFrame frame) => pcmOfFrame(frame);
}

/// A tap that has not come off, and what is still trying, if anything is.
class _UnreleasedTap {
  final DetachTap detach;

  /// The detach already in flight. Null when it threw rather than hung, which
  /// is the only case where asking again is safe.
  final Future<void>? running;

  const _UnreleasedTap(this.detach, this.running);
}
