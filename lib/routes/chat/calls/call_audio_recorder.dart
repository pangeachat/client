// Dart imports:
import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

// Package imports:
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:matrix/matrix.dart';

// Project imports:
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_writer.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

/// Uploads bytes to this homeserver's media repository, returning the `mxc://`
/// URI they land at. Injected so the recorder is testable without a
/// homeserver; the real one is `Client.uploadContent`.
///
/// PLAIN, never encrypted: Pangea creates its rooms unencrypted (see
/// `transcript_writer.dart`'s own `encrypted` parameter for the precedent), so
/// there is no attached-file key or IV to produce here, and nothing on the
/// read side ever needs to decrypt anything.
typedef CallAudioUploader =
    Future<Uri> Function(
      Uint8List bytes, {
      required String filename,
      required String contentType,
    });

/// A second, independent consumer of this device's own outbound call audio --
/// the call-audio-recording half, fed BESIDE (never instead of) the
/// speech-to-text sink `CallCaptureService.sink` already carries. See
/// [CallCaptureService.audioRecording] for the exact points this is called
/// from.
///
/// A seam rather than a single callback because the writer needs three
/// distinct facts a plain frame stream cannot carry on its own: where a run
/// BEGAN (for the alignment offset), that a run has ENDED (so a generation can
/// be finalised before anything asks to send it), and that the CALL is over
/// (the one moment sending is even considered).
abstract class CallAudioRecordingSink {
  /// A new uninterrupted stretch of this device's own outbound audio has
  /// begun. [runStartedAtMs] is the run's own start position -- the SAME
  /// conversion (`CallCaptureService._runStartsAt`) the transcript chunker's
  /// own `runStartedAtMs` is built from, so the two consumers of one tap can
  /// never disagree about when a run began, even though this one now opens
  /// independently of whether the transcript's own chunker exists (see
  /// `CallCaptureService._audioRunFormat` for why the two are tracked apart).
  ///
  /// A NEW generation in the recorder's own terms: whatever the previous one
  /// held, and had not yet been authorised to send, is superseded. Only the
  /// LATEST stretch of carrying is ever a candidate for upload -- splicing
  /// several stretches into one container, with the silence between them
  /// represented correctly, is a materially harder problem than this
  /// prototype takes on. A device displaced and re-elected mid-call ends up
  /// sending, at most, the audio from the stretch it was carrying when the
  /// call ended.
  void onRunStarted(int runStartedAtMs, int sampleRate, int channels);

  /// One frame of the run [onRunStarted] most recently opened.
  ///
  /// MUST NOT block and MUST NOT throw an exception the caller cannot
  /// recover from -- a second consumer's failure must never slow or take down
  /// the speech-to-text path it sits beside. [samples] is already digital
  /// silence, sample for sample, for any interval the learner spent muted:
  /// the caller substitutes it before this is reached (see
  /// [CallCaptureService]'s own fan-out), so nothing here needs to know the
  /// mute gate exists to get a mute right.
  void onFrame(Int16List samples);

  /// The run [onRunStarted] opened has ended -- a stop, a tap death, or a
  /// format change (a mute does NOT end it; see [CallCaptureService]'s own
  /// docs on why the recording's run boundary and the transcript chunker's
  /// have to differ on exactly that one point).
  void onRunEnded();

  /// The call is over. [wasCarrier] is whether this device was still attached
  /// and running the instant the caller decided to stop capturing for
  /// good -- read once, before that decision could change it, so this is the
  /// one place this sink may trust the answer. It is fed
  /// `CallCaptureService.wasCarryingBeforeLastStop`, NOT the ownership arbiter's
  /// unrelated `carriedOn`; the name says `carrier` so the two cannot be
  /// confused at the call site. [callKey] is the anchor the half relates to,
  /// read fresh because it may not have existed when this sink was built.
  ///
  /// THE gate. Nothing upstream of this may assume it has already excluded a
  /// non-carrying device -- see `CallCaptureService`'s own docs on where
  /// [wasCarrier] comes from and why it cannot be derived any later than this.
  Future<void> finish({required bool wasCarrier, required String? callKey});
}

/// Where upload/send progress for one call-audio half is remembered, keyed by
/// its own deterministic transaction id.
///
/// Two different failures this closes, at two different distances. Within
/// ONE `finish()` call, a retry that only failed at the send step must not
/// upload the recording's bytes a second time -- that much [_AudioGeneration]
/// already guaranteed on its own, in memory. This interface exists for the
/// distance beyond that: an upload that lands at the homeserver but whose
/// response is lost to a client-side timeout, or a process that is killed
/// between the upload landing and the event being sent, would otherwise have
/// no record that the blob already exists -- and the concrete store used in
/// production persists past both.
///
/// Injected so the recorder is testable without touching real device
/// storage; see [InMemoryCallAudioUploadStateStore] for the one used there,
/// and `call_session.dart` for the real, `SharedPreferences`-backed wiring.
abstract class CallAudioUploadStateStore {
  /// The persisted state for [txnId], or null when nothing has been saved for
  /// it yet. Never throws about content it cannot parse; returns null.
  Future<Map<String, dynamic>?> read(String txnId);

  /// Persists [state] under [txnId], replacing whatever was stored before.
  Future<void> write(String txnId, Map<String, dynamic> state);
}

/// Holds state in memory only. The default when nothing else is injected,
/// which is every test and any deployment that has not wired a durable one:
/// retries within one `finish()` call are still deduplicated (by
/// [_AudioGeneration.uploadedUrl] directly), and only the CROSS-RESTART case
/// [CallAudioUploadStateStore] exists for is what this does not cover.
class InMemoryCallAudioUploadStateStore implements CallAudioUploadStateStore {
  final Map<String, Map<String, dynamic>> _byTxnId = {};

  @override
  Future<Map<String, dynamic>?> read(String txnId) async => _byTxnId[txnId];

  @override
  Future<void> write(String txnId, Map<String, dynamic> state) async {
    _byTxnId[txnId] = Map.of(state);
  }
}

/// One continuous attempt at recording this device's own outbound audio.
///
/// Mutable by design -- [canceled] flips under a superseding
/// [CallAudioRecorder.onRunStarted] or an explicit
/// [CallAudioRecorder.cancelOwnership] call that can land WHILE
/// [CallAudioRecorder.finish] is still working through this very generation,
/// which is the one case [finish] has to notice mid-flight.
class _AudioGeneration {
  /// Identifies this generation, and only this one -- across the whole
  /// call, never reused, and never reused across a RESTART either. This is
  /// what [CallAudioRecorder.finish] ties a persisted upload record to: the
  /// store is keyed by the call's transaction id, which names the CALL
  /// (call key, sender, device) and is the SAME for every generation of it,
  /// so a persisted URL from an earlier, since-superseded generation would
  /// otherwise be indistinguishable from one this generation itself
  /// produced. See [CallAudioUploadStateStore]'s own docs and the
  /// `generation_id` field in what gets persisted.
  ///
  /// A STRING, timestamp-plus-random rather than a simple in-process
  /// counter -- see [CallAudioRecorder._newGenerationId] for the full
  /// argument. A counter reset to 0 by every fresh `CallAudioRecorder`
  /// would collide EXACTLY with an earlier, still-persisted generation's id
  /// from before a process restart, which is precisely the case this field
  /// exists to rule out: the store survives the restart even though the
  /// counter does not.
  final String id;

  final int sampleRate;
  final int channels;
  final int runStartedAtMs;

  _AudioGeneration({
    required this.id,
    required this.sampleRate,
    required this.channels,
    required this.runStartedAtMs,
  });

  final BytesBuilder _buffer = BytesBuilder(copy: true);
  int bytesWritten = 0;

  /// Whether this generation has been superseded or explicitly revoked. Once
  /// true, nothing may upload or send on its behalf -- checked before EVERY
  /// network step in [CallAudioRecorder.finish], not merely once at entry,
  /// because it can flip while those steps are in flight.
  bool canceled = false;

  /// Whether the size/duration cap has already been logged for this
  /// generation, so a long capped call does not spam one warning per frame.
  bool cappedLogged = false;

  /// The upload's own result, cached so a retried [CallAudioRecorder.finish]
  /// does not upload the same bytes twice. The deterministic transaction id
  /// already dedups the EVENT server-side; this, together with
  /// [CallAudioUploadStateStore], is what dedups the BLOB.
  Uri? uploadedUrl;

  /// Whether the send has been CONFIRMED durable -- a non-null event id
  /// actually came back, not merely attempted. This is what
  /// [CallAudioRecorder._finish]'s own exit-guard reads to tell a real half
  /// from an orphan: a blob can only be an orphan if it was uploaded AND
  /// never durably sent, and this is the one flag that says which
  /// happened, regardless of which of [CallAudioRecorder._finish]'s many
  /// exit paths got there.
  bool sent = false;

  /// Whether [CallAudioRecorder._logOrphan] has already reported
  /// [uploadedUrl] once for this generation. `CallRecord.finish()` can
  /// legitimately call [CallAudioRecorder.finish] more than once for the
  /// same call (see `_finishing`'s own docs), and every one of those calls
  /// reaches the SAME exit-guard with the SAME [uploadedUrl] still set and
  /// [sent] still false -- without this, each one would re-report the
  /// identical orphan, growing without bound the more times ownership
  /// changes hands. Set the instant the orphan is first logged, checked
  /// before every later attempt to log it again, by both the exit-guard
  /// and the upload-future observer (see [CallAudioRecorder._logOrphan]
  /// itself for why those are the only two callers).
  bool orphanLogged = false;

  void append(Uint8List bytes, int maxBytes) {
    final room = maxBytes - bytesWritten;
    if (room <= 0) return;
    final take = bytes.length <= room
        ? bytes
        : Uint8List.sublistView(bytes, 0, room);
    _buffer.add(take);
    bytesWritten += take.length;
  }

  Uint8List takeBytes() => _buffer.toBytes();

  int get _bytesPerFrame => 2 * channels;

  Duration get duration => Duration(
    microseconds: (bytesWritten ~/ _bytesPerFrame) * 1000000 ~/ sampleRate,
  );
}

/// Thrown internally to unwind [CallAudioRecorder.finish]'s retry loop the
/// instant ownership is lost while a network step is in flight, rather than
/// waiting for that step to settle naturally. Never escapes [finish] itself.
class _AudioRecordingCanceled implements Exception {
  const _AudioRecordingCanceled();
}

/// Records this device's own outbound call audio into ONE valid WAV
/// container, and publishes it as a `pangea.call_audio` half at the end of
/// the call -- the sibling `writeCallTranscript` produces for text.
///
/// LOCAL PROTOTYPE, deliberately narrower than the transcript path it sits
/// beside:
///
/// * Save-at-finish, not progressive. Nothing here is durable before
///   [finish] runs, so a crash between the last frame and the end of the call
///   loses the whole half, not just its tail. `CallTranscriptSink` avoids this
///   by shipping each chunk as it completes; this does not, because a WAV
///   file has one header describing the whole of its data and cannot be
///   grown incrementally on the wire the way independent chunks can.
/// * One generation survives at a time. See [onRunStarted] -- a device
///   displaced and re-elected mid-call sends only its LAST stretch of
///   carrying, never a splice of several.
/// * A canceled generation is guaranteed to send no EVENT -- never a
///   room-visible artifact, never a credit -- but NOT guaranteed to upload
///   no BLOB. `Client.uploadContent` (and this app's HTTP layer generally,
///   see `CallUploadGate`'s own docs) offers no request-level cancellation,
///   so an upload already in flight when ownership is lost can still land
///   at the homeserver; this recorder only stops WAITING for it and never
///   USES the result. The cost is a plain (Pangea rooms are unencrypted),
///   orphaned blob nothing will ever reference -- logged when it is
///   detected (see the class's own `finish` for where), and otherwise left
///   to whatever retention the homeserver's media repository applies on its
///   own. Accepted on the same terms `finish`'s own class docs already
///   accept a crash losing the whole half: a real limitation of a
///   prototype with no server-side deletion story, not a silent one.
/// * Accumulated in memory, not spooled to a temp file. `StreamingSttSession`
///   (`streaming_stt_session.dart`) already accumulates a call's retained WAV
///   the same way for the same reason: [pcm16ToWav] needs the whole byte
///   range to compute a header, `Client.uploadContent` needs the whole range
///   in memory to POST it, and holding it once, bounded at [maxBytes], costs
///   nothing a native temp file would have saved -- while a bounded in-memory
///   buffer is the ONE spooling strategy that needs no platform-specific code
///   at all, so this needs no `path_provider` and runs identically in a unit
///   test and on every platform this app ships to.
class CallAudioRecorder implements CallAudioRecordingSink {
  final String senderId;
  final String? deviceId;
  final CallAudioSender send;
  final CallAudioUploader upload;

  /// Read FRESH at [finish], not at [onRunStarted]: the SFU's join stamp can
  /// arrive after the recording has already started (a slow handshake, a
  /// reconnect), and reading it early left this half with no anchor while the
  /// transcript half -- which reads `media.clockAnchor` at finish, once the
  /// call has had its whole length to receive one -- carried a perfectly good
  /// one. Reading both at the SAME point, from the SAME source, is what keeps
  /// a device's two halves from disagreeing about whether alignment exists at
  /// all.
  final ClockAnchor? Function() clockAnchor;

  /// The size and duration ceiling for one recording. Past either, further
  /// audio is silently (but LOGGED, once) not appended -- the recording is
  /// simply shorter than the call, never corrupted or refused outright. See
  /// [_AudioGeneration.append].
  final int maxBytes;
  final Duration maxDuration;

  final int deliveryAttempts;

  /// The unit a retry's backoff is measured in -- attempt N waits N of these.
  /// Zero in tests that do not care about timing; the real default mirrors
  /// `CallRecord`'s own one-second unit.
  final Duration retryDelay;

  /// Where upload/send progress is remembered past one `finish()` attempt.
  /// See [CallAudioUploadStateStore]'s own docs for exactly what this closes
  /// that in-memory caching on [_AudioGeneration] alone does not.
  final CallAudioUploadStateStore uploadStateStore;

  /// How many frames [onFrame] will hold queued for the background pump
  /// before it starts dropping them. See [onFrame] for why a bound exists at
  /// all, and [_pump] for where the queue actually drains.
  final int maxPendingFrames;

  static const _defaultMaxBytes = 60 * 1024 * 1024;
  static const _defaultMaxDuration = Duration(minutes: 30);
  static const _defaultDeliveryAttempts = 3;
  static const _defaultRetryDelay = Duration(seconds: 1);
  static const _defaultMaxPendingFrames = 64;

  CallAudioRecorder({
    required this.senderId,
    required this.deviceId,
    required this.send,
    required this.upload,
    ClockAnchor? Function()? clockAnchor,
    this.maxBytes = _defaultMaxBytes,
    this.maxDuration = _defaultMaxDuration,
    this.deliveryAttempts = _defaultDeliveryAttempts,
    this.retryDelay = _defaultRetryDelay,
    CallAudioUploadStateStore? uploadStateStore,
    this.maxPendingFrames = _defaultMaxPendingFrames,
  }) : clockAnchor = clockAnchor ?? _noAnchor,
       uploadStateStore =
           uploadStateStore ?? InMemoryCallAudioUploadStateStore();

  static ClockAnchor? _noAnchor() => null;

  _AudioGeneration? _current;

  /// The current generation's own identity, or null when none is open.
  /// Exposed only so a test can construct a persisted record this exact
  /// generation would (or, for a DIFFERENT generation's id, would not)
  /// recognise as its own -- production code never needs this, because
  /// [finish] already has [_current] in hand directly.
  @visibleForTesting
  String? get currentGenerationId => _current?.id;

  /// Shared rather than reseeded per call: `Random()`'s own default
  /// constructor already seeds from the system, and one instance avoids
  /// paying that cost -- and any risk of two seeds landing close together
  /// on a fast platform clock -- every time a run starts.
  static final Random _idRandom = Random();

  /// Mints [_AudioGeneration.id]: the wall clock, to the microsecond, plus a
  /// random tail, joined into one string. Never a simple in-process
  /// counter (`0, 1, 2, ...`) -- a counter resets to 0 on every fresh
  /// `CallAudioRecorder`, which means every process restart mid-call would
  /// start over at exactly the value an EARLIER, still-persisted generation
  /// from before the restart already used, and collide with it outright.
  /// [CallAudioUploadStateStore] is deliberately durable past a restart (see
  /// its own docs); the id naming what it stores has to survive one too.
  ///
  /// Not fetched from the store itself, which would be the more obviously
  /// "globally coordinated" approach: that reads make this async, and
  /// [onRunStarted] is called synchronously from the exact callback that
  /// also feeds the speech-to-text chunker, which cannot be made to wait on
  /// I/O. Timestamp-plus-random needs no coordination and is exactly as
  /// synchronous as the call site requires; a same-microsecond collision
  /// between two generations, in one process, is already effectively
  /// impossible, and [_idRandom]'s own randomness on top makes it more so.
  ///
  /// The bound is `0x40000000` (2^30), NOT `1 << 32`: on the web (dart2js) a
  /// shift of 32 overflows to 0, so `Random.nextInt(0)` threw a RangeError
  /// synchronously here -- on the very first frame, before any generation
  /// existed -- which silently killed call-audio recording on the WEB entirely.
  /// The transcript mints no id and was undisturbed, so nothing surfaced the
  /// failure. 2^30 is a legal `nextInt` bound on every platform (native ints are
  /// 64-bit, dart2js keeps 2^30 well inside 32 bits) and, beside the microsecond
  /// timestamp, is ample entropy against a same-microsecond collision.
  static String _newGenerationId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idRandom.nextInt(0x40000000)}';

  int _capBytes(_AudioGeneration gen) {
    final byTime =
        gen.sampleRate * gen.channels * 2 * maxDuration.inMilliseconds ~/ 1000;
    return maxBytes < byTime ? maxBytes : byTime;
  }

  // ---------------------------------------------------------------- capture

  /// Frames queued for [_pump], paired with the generation each belonged to
  /// AT THE INSTANT [onFrame] enqueued it -- never resolved against whatever
  /// [_current] happens to be when the queue finally drains. A generation
  /// superseded between the two keeps the frames it was actually given; a
  /// frame is never retroactively handed to the generation that replaced it,
  /// and never silently reattributed either way.
  final Queue<(Int16List, _AudioGeneration)> _pending =
      Queue<(Int16List, _AudioGeneration)>();

  bool _pumpScheduled = false;
  bool _backpressureLogged = false;

  /// Completes the moment the queue is fully drained, for [finish] (or a
  /// test) to await. Cleared and re-created per drain rather than reused,
  /// since a completer only ever fires once.
  Completer<void>? _drainWaiter;

  @override
  void onRunStarted(int runStartedAtMs, int sampleRate, int channels) {
    // Superseded, not merely replaced: a [finish] already under way for the
    // OLD generation reads this flag before every network step it still has
    // to take, so a new run beginning here reliably stops a stale send even
    // when it lands mid-upload.
    _cancelCurrent();
    _current = _AudioGeneration(
      id: _newGenerationId(),
      sampleRate: sampleRate,
      channels: channels,
      runStartedAtMs: runStartedAtMs,
    );
  }

  /// Queues [samples] for the background pump and returns immediately.
  ///
  /// MUST NOT do the actual byte copy inline: [CallCaptureService] calls this
  /// synchronously from the exact callback that also feeds the
  /// speech-to-text chunker, in the SAME call stack the platform's audio
  /// tap delivers a frame on. Appending a batch to a `BytesBuilder` is cheap
  /// today, but the contract this sink promises its caller -- "MUST NOT
  /// block" -- has to hold regardless of how expensive a future change to
  /// [_AudioGeneration.append] turns out to be, and a caller that relied on
  /// "it happens to be fast right now" would have no warning when that
  /// stopped being true. Deferring the actual work to a microtask, behind a
  /// BOUNDED queue that drops and logs once it falls behind, is what makes
  /// that a structural guarantee rather than an accident of the current
  /// implementation.
  @override
  void onFrame(Int16List samples) {
    final gen = _current;
    // Defensive rather than reachable: [CallCaptureService] never calls
    // [onFrame] without an [onRunStarted] before it in the same run. Dropped
    // silently because there is nothing sensible to attribute an orphaned
    // frame to, and this is not a failure the recording itself can report.
    if (gen == null || gen.canceled) return;
    if (_pending.length >= maxPendingFrames) {
      // ONCE, not per dropped frame: a call that falls permanently behind
      // would otherwise log once per audio frame -- tens of times a second --
      // for the rest of the call.
      if (!_backpressureLogged) {
        _backpressureLogged = true;
        Logs().w(
          'Call audio recording is falling behind; dropping frames rather '
          'than slowing speech-to-text',
        );
      }
      return;
    }
    _pending.add((samples, gen));
    if (!_pumpScheduled) {
      _pumpScheduled = true;
      scheduleMicrotask(_pump);
    }
  }

  /// Drains [_pending] onto whichever generation each frame actually belongs
  /// to, entirely off the caller's own call stack.
  void _pump() {
    _pumpScheduled = false;
    while (_pending.isNotEmpty) {
      final (samples, gen) = _pending.removeFirst();
      // Superseded or cancelled between being queued and being drained: the
      // bytes belong to a generation nothing will ever send, so they are
      // simply not appended -- never redirected to whatever IS current now,
      // which was not the generation this frame was captured for.
      if (gen.canceled) continue;
      final bytes = Uint8List.view(
        samples.buffer,
        samples.offsetInBytes,
        samples.lengthInBytes,
      );
      final before = gen.bytesWritten;
      gen.append(bytes, _capBytes(gen));
      if (gen.bytesWritten == before && bytes.isNotEmpty && !gen.cappedLogged) {
        gen.cappedLogged = true;
        Logs().w(
          'Call audio recording reached its ${maxBytes ~/ (1024 * 1024)}MB / '
          '${maxDuration.inMinutes}min cap; the rest of this call is not '
          'recorded to this half',
        );
      }
    }
    final waiter = _drainWaiter;
    _drainWaiter = null;
    waiter?.complete();
  }

  /// Waits for every frame queued so far to be applied to its generation.
  ///
  /// [finish] calls this before it reads any generation's bytes: encoding a
  /// WAV from bytes that have not caught up with the frames already handed
  /// to [onFrame] would silently ship a recording short of what was actually
  /// captured.
  ///
  /// A LOOP, not a single await: completing [_drainWaiter] resumes this
  /// method's own caller on a LATER microtask, never the same one -- so a
  /// frame that arrives in that gap (a caller that has not yet fully
  /// stopped feeding this sink) would otherwise be missed by a check made
  /// only once, before the wait. Re-checking after every wait is what makes
  /// this correct regardless of how many such frames land in a row, rather
  /// than relying on the caller to guarantee none ever will.
  Future<void> _drainPending() async {
    while (_pending.isNotEmpty || _pumpScheduled) {
      await (_drainWaiter ??= Completer<void>()).future;
    }
  }

  @override
  void onRunEnded() {
    // Nothing to do here: the generation simply stops receiving frames until
    // either a new [onRunStarted] supersedes it, or [finish] uses it. Kept as
    // an explicit method (rather than folded away) because it is where a
    // future crash-safe upload would start flushing -- see the class-level
    // docs on what this prototype defers.
  }

  /// Completes the moment ownership is lost, for a network step in
  /// [finish] to race against instead of blocking on regardless. Created
  /// lazily by [finish] itself; null whenever nothing is waiting on it.
  Completer<void>? _cancelSignal;

  void _cancelCurrent() {
    final gen = _current;
    if (gen != null) gen.canceled = true;
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  /// Callable by anything that later learns ownership was revoked out of
  /// band, before a fresh [onRunStarted] would otherwise notice it.
  /// [onRunStarted]'s own auto-supersede already exercises this same path
  /// automatically whenever a new stretch of carrying begins; this exists for
  /// the case where ownership is lost and never regained before the call
  /// ends, so nothing else would ever flip it.
  void cancelOwnership() => _cancelCurrent();

  // ------------------------------------------------------------------ send

  static const _giveUpKey = 'call_audio_recorder.upload_failed';

  /// The in-flight [finish], so a second caller joins it rather than running
  /// a second one alongside it.
  ///
  /// Not a theoretical concern: `CallRecord.finish()` -- the one real caller
  /// -- is itself reachable twice for the same call ("a hangup and a
  /// disconnect routinely arrive together", per its own docs), and it calls
  /// [finish] here unconditionally on every invocation, with no guard of its
  /// own (unlike its transcript-publishing sibling, which the deterministic
  /// event id makes safe to call twice regardless). Two concurrent
  /// executions of [_finish] would each mint their OWN [_cancelSignal] and
  /// overwrite the other's in [_cancelSignal] itself -- so
  /// [cancelOwnership] would only ever be able to wake ONE of the two races,
  /// and the other would sit blocked on an upload nothing will ever tell it
  /// to give up on. Joining one execution removes the second race entirely,
  /// rather than trying to keep two `_cancelSignal`s straight.
  Future<void>? _finishing;

  @override
  Future<void> finish({required bool wasCarrier, required String? callKey}) {
    return _finishing ??= _finish(
      wasCarrier: wasCarrier,
      callKey: callKey,
    ).whenComplete(() => _finishing = null);
  }

  /// Logs WHY one attempt gave up -- nothing more. Five straight gate
  /// rounds each found a NEW site in [_finish] that reported an abandoned
  /// attempt without naming the already-uploaded blob it left behind, one
  /// site at a time; the url-orphan guarantee no longer lives at any of
  /// these call sites at all, so there is no site left to individually get
  /// that part wrong. See [_finish]'s own exit-guard -- the `finally`
  /// wrapping its whole body -- for the SINGLE place that now decides, and
  /// [_logOrphan] for the one message it logs when it does.
  static void _logAbandonment(String reason) {
    Logs().i('Call audio half abandoned: $reason');
  }

  /// The one message an orphaned blob is ever reported with -- EXACTLY
  /// once per generation, guarded by [_AudioGeneration.orphanLogged], no
  /// matter how many times this is called for the same [gen]. That guard
  /// is what keeps a call_key's orphan from being re-reported every time a
  /// LATER `finish()` call reaches the same conclusion about the same
  /// still-un-sent upload -- `CallRecord.finish()` can legitimately call
  /// [finish] more than once for the same call (see `_finishing`'s own
  /// docs), and each one reaches [_finish]'s exit-guard with the identical
  /// [_AudioGeneration.uploadedUrl] and [_AudioGeneration.sent] still
  /// false, which without this latch would look like a brand new orphan
  /// every time.
  ///
  /// Called from exactly two places, not one call per site: [_finish]'s
  /// own exit-guard, which covers every timing where the orphan is already
  /// knowable by the moment [_finish] itself returns (a cancellation
  /// noticed at any check, every delivery attempt failing outright, or any
  /// other exit that leaves [_AudioGeneration.uploadedUrl] set without
  /// [_AudioGeneration.sent] ever becoming true) -- and the upload-future
  /// observer inside the retry loop, which needs its own call because it
  /// can fire strictly AFTER [_finish] has already returned, once the
  /// `finally` that would otherwise have caught this has already run (see
  /// that callback's own docs for why [_AudioGeneration.uploadedUrl] is not
  /// even set yet at that point either). Sharing this ONE gate between them
  /// is what stops the exit-guard and the observer from BOTH logging the
  /// same url, on the off chance a future change ever put them in a
  /// position to.
  static void _logOrphan(_AudioGeneration gen, Uri url) {
    if (gen.orphanLogged) return;
    gen.orphanLogged = true;
    Logs().w(
      'A call-audio blob at $url is now an orphan no event will ever '
      'reference',
    );
  }

  Future<void> _finish({
    required bool wasCarrier,
    required String? callKey,
  }) async {
    // Ahead of every guard below: a generation's bytes are not final until
    // every frame handed to [onFrame] has actually been applied to it, and
    // reading them one microtask early would ship a recording short of what
    // was truly captured.
    await _drainPending();

    final gen = _current;
    if (!wasCarrier) {
      Logs().i(
        'No call audio half sent: this device was not carrying the '
        'recording when the call ended',
      );
      return;
    }
    if (gen == null) {
      Logs().i(
        'No call audio half sent: this device never recorded audio this call',
      );
      return;
    }
    // From here on `gen` is definitely non-null, and every remaining exit
    // path -- a cancellation noticed at any of several checks, every
    // delivery attempt failing outright, or simply returning once the send
    // is confirmed -- has to be checked for an upload that landed but was
    // never durably sent. This `finally`, wrapping the whole rest of the
    // method, is what makes that true STRUCTURALLY rather than by each exit
    // path remembering to check: five straight gate rounds each found a new
    // site that forgot to, one at a time, which is the rule needing
    // enforcement in one place rather than five (now six) copies of the
    // same branch. See [_logOrphan]'s own docs for the one timing this
    // cannot reach, and why that one still needs its own call.
    try {
      if (gen.canceled) {
        // Reachable before the retry loop even starts: `CallRecord.finish()`
        // -- see [_finishing]'s own docs -- can legitimately call [finish]
        // twice for the same call, and a first call that uploaded
        // successfully but then exhausted every delivery attempt on the
        // SEND leaves that url on [gen] for whichever call notices
        // ownership is gone next, even a later one that never reaches the
        // loop below at all.
        _logAbandonment(
          'the recording generation was superseded before it could be sent',
        );
        return;
      }
      if (callKey == null || callKey.isEmpty) {
        Logs().w(
          'No call audio half sent: the call has no anchor to relate to',
        );
        return;
      }

      final txnId = CallAudioContent.txnId(callKey, senderId, deviceId);

      // Best-effort: a store that cannot be read is treated as empty, never
      // as a reason to refuse sending a recording this device actually
      // holds.
      Map<String, dynamic>? persisted;
      try {
        persisted = await uploadStateStore.read(txnId);
      } catch (e, s) {
        Logs().w('Could not read the persisted call-audio upload state', e, s);
      }
      if (persisted?['status'] == 'sent') {
        // Already landed on an earlier attempt -- possibly in a process
        // that has since restarted -- and the deterministic transaction id
        // means a resend would only collapse server-side anyway. Skipped
        // here instead to save the upload's own bytes leaving the device a
        // second time. [gen.uploadedUrl] is never populated in this branch
        // (the read below that would do it is skipped by this early
        // return), so the exit-guard above has nothing to false-positive
        // on here regardless of whether this is the SAME generation that
        // sent it or a fresh one reading a pre-restart record.
        Logs().i(
          'No call audio half sent: this call\'s half was already sent '
          '(persisted state)',
        );
        return;
      }
      // Trusted ONLY for the SAME generation that produced it. The store is
      // keyed by [txnId], which names the CALL (call key, sender, device)
      // and is identical across every generation of it -- so without this
      // check, a generation uploaded and persisted, then superseded before
      // it could send, would have its URL handed to whichever LATER
      // generation happens to run `finish()` next. That generation's own
      // bytes, duration and alignment would then be published pointing at a
      // DIFFERENT recording's audio -- a data-integrity bug, not merely a
      // wasted upload, because the event that resulted would look entirely
      // valid while being wrong.
      if (persisted?['generation_id'] == gen.id) {
        final persistedUrl = persisted?['mxc_url'];
        if (persistedUrl is String) {
          final parsed = Uri.tryParse(persistedUrl);
          // Validated, not merely parsed: `Uri.tryParse` accepts an empty
          // string and any relative one without complaint, and a persisted
          // record this reader cannot vouch for -- corrupted on disk, or
          // written by some future version of this code in a different
          // shape -- must read as NO url rather than as a real one. Beyond
          // the scheme and host, an `mxc://server` with no media-id path
          // segment ALSO parses cleanly and ALSO names nothing playable --
          // Matrix's own content URI shape is `mxc://server/media-id`, and a
          // reference missing the second half is exactly as untrustworthy
          // as an empty string. An event sent with a garbage `url` field is
          // a half nobody can play, which is worse than the wasted upload a
          // false negative here costs at most.
          if (parsed != null &&
              parsed.scheme == 'mxc' &&
              parsed.host.isNotEmpty &&
              parsed.pathSegments.isNotEmpty &&
              parsed.pathSegments.first.isNotEmpty) {
            gen.uploadedUrl = parsed;
          }
        }
      }

      // Read HERE, once, from the SAME source and at the SAME point in the
      // call's life the transcript half reads its own `media.clockAnchor`
      // -- see [clockAnchor]'s own docs for why an earlier version reading
      // this at [onRunStarted] could leave the two halves disagreeing about
      // whether an anchor existed at all.
      final anchor = clockAnchor();
      final offsetMs = anchor == null
          ? null
          : gen.runStartedAtMs - anchor.deviceMs;

      final wav = pcm16ToWav(
        gen.takeBytes(),
        sampleRate: gen.sampleRate,
        channels: gen.channels,
      );
      final durationMs = gen.duration.inMilliseconds;

      final cancelSignal = _cancelSignal = Completer<void>();
      try {
        Object? lastError;
        StackTrace? lastStack;
        for (var attempt = 0; attempt < deliveryAttempts; attempt++) {
          if (gen.canceled) {
            _logAbandonment('ownership was lost while it was being sent');
            return;
          }
          if (attempt > 0) await Future.delayed(retryDelay * attempt);
          // Checked AGAIN, immediately after the backoff: the delay above
          // is real time the recorder is not otherwise watching, and
          // ownership can be lost during it just as easily as during the
          // upload itself. Without this, a cached [gen.uploadedUrl] from an
          // earlier attempt would skip straight to the send-time check
          // further down -- fine on its own -- but a NOT-yet-uploaded
          // generation would still INITIATE a fresh upload attempt below
          // before the race inside it ever got a chance to notice a
          // cancellation that had already happened.
          if (gen.canceled) {
            _logAbandonment(
              'ownership was lost while this attempt was waiting to retry',
            );
            return;
          }
          try {
            // Reused across attempts, and across a restart if the durable
            // store found a match above: the deterministic transaction id
            // already dedups the EVENT server-side, and this is what dedups
            // the BLOB -- a retry must not upload the same recording twice.
            var url = gen.uploadedUrl;
            if (url == null) {
              // Raced against ownership loss rather than merely awaited:
              // uploading is the one genuinely slow step, and there is no
              // reason to go on WAITING for, or USING, an answer that has
              // stopped mattering. `Future.any` returns the moment either
              // side settles; the loser is simply never awaited again HERE.
              //
              // "Abort the upload" is honoured only as far as this client
              // truly can: `Client.uploadContent` offers no request-level
              // cancellation (see `CallUploadGate`'s own docs -- this app's
              // whole HTTP layer does not either), and the one lever that
              // DOES exist -- closing the shared `http.Client` every other
              // request on this connection also uses -- would abort syncs
              // and sends across the whole app to cancel one upload, which
              // is not a trade this feature may make on its own. So the
              // upload below is free to keep running and land at the
              // homeserver regardless of the race's outcome; what this
              // recorder guarantees is narrower than "no blob" -- see the
              // class docs' own "no request-level abort" bullet -- and is
              // enforced by never using a URL this race did not itself
              // produce.
              final uploadFuture = upload(
                wav,
                filename: 'call_audio.wav',
                contentType: 'audio/wav',
              );
              // Observed separately from the race below, so a losing
              // upload that lands anyway is at least LOGGED rather than
              // silently becoming an untraceable orphan -- the one piece of
              // "no silent failures" available here, since nothing on this
              // client can stop the bytes from actually arriving.
              //
              // Calls [_logOrphan] directly rather than relying on the
              // exit-guard above: when cancellation wins the race below
              // BEFORE this upload resolves, [_finish] leaves
              // [gen.uploadedUrl] unset and returns through the catch
              // further down, so the exit-guard's own check has ALREADY run
              // and found nothing to report by the time this callback
              // finally fires, on some LATER microtask, possibly well after
              // [_finish] itself has returned.
              unawaited(
                uploadFuture.then((landedUrl) {
                  if (cancelSignal.isCompleted) _logOrphan(gen, landedUrl);
                }, onError: (Object _, StackTrace _) {}),
              );
              url = await Future.any<Uri>([
                uploadFuture,
                cancelSignal.future.then(
                  (_) => throw const _AudioRecordingCanceled(),
                ),
              ]);
              // In memory FIRST, and deliberately not made to depend on the
              // durable write below succeeding: [gen.uploadedUrl] is what
              // THIS attempt's own retries key off, and the upload already
              // genuinely happened -- refusing to use it because an
              // optional local write hiccuped would throw away a real
              // recording over a failure that has nothing to do with
              // whether it landed. A failed write here costs only the
              // CROSS-RESTART case [CallAudioUploadStateStore] exists for,
              // on the exact terms the class-level docs already accept for
              // a crash generally: logged, not fatal.
              gen.uploadedUrl = url;
              try {
                await uploadStateStore.write(txnId, {
                  'call_key': callKey,
                  'sender': senderId,
                  'device': deviceId,
                  'txn_id': txnId,
                  // Ties this record to the generation whose bytes are
                  // actually at this url -- see [_AudioGeneration.id]'s own
                  // docs and the read site above that checks it back.
                  'generation_id': gen.id,
                  'mxc_url': url.toString(),
                  'status': 'uploaded',
                });
              } catch (e, s) {
                Logs().w('Could not persist the call-audio upload state', e, s);
              }
            }

            // Checked AGAIN, immediately before the send: the step above
            // was the one genuinely slow one, and ownership can have moved
            // on while it ran.
            if (gen.canceled) {
              _logAbandonment('before it could be sent');
              return;
            }

            // Raced against ownership loss on the SAME terms the upload
            // above is: `send` -- `Room.sendEvent` in production -- offers
            // no cancellation contract either, so this does not stop the
            // event from reaching the homeserver. What it stops is USING
            // the result: a cancellation that wins this race means
            // [gen.sent] is never set, and this attempt reports itself
            // abandoned rather than confirmed. See the class docs' "no
            // duplicate event, ever" bullet for the one guarantee this
            // still gives up: the deterministic transaction id means a send
            // that DID land under the hood cannot become a second,
            // different event later, whichever generation's `finish()`
            // eventually notices.
            final eventId = await Future.any<String?>([
              writeCallAudioEvent(
                send: send,
                callKey: callKey,
                senderId: senderId,
                deviceId: deviceId,
                url: url.toString(),
                mimetype: 'audio/wav',
                size: wav.length,
                durationMs: durationMs,
                sampleRate: gen.sampleRate,
                channels: gen.channels,
                clockAnchor: anchor,
                recordingStartedOffsetFromDeviceJoinMs: offsetMs,
              ),
              cancelSignal.future.then(
                (_) => throw const _AudioRecordingCanceled(),
              ),
            ]);
            if (eventId == null) {
              // `send` -- `Room.sendEvent` in production -- returns null
              // EXACTLY when the send did not durably succeed (a
              // `MatrixException`, an oversized event, or a client-side
              // timeout, all without throwing; see its own implementation),
              // never as a quieter kind of success. Treated as a FAILED
              // attempt like any other: falling through to set [gen.sent]
              // here would permanently drop a valid resend, because the
              // next attempt would see this persisted state and refuse to
              // try again for a half that was never actually written.
              throw StateError(
                'The homeserver did not confirm the call-audio event was '
                'sent',
              );
            }
            // In memory FIRST, on the exact same terms [gen.uploadedUrl]
            // above already is: this is what the exit-guard above reads to
            // know the upload it is looking at was not abandoned, and it
            // must be true the instant the homeserver confirms the send,
            // not only once the optional local write below also succeeds.
            gen.sent = true;
            try {
              await uploadStateStore.write(txnId, {
                'call_key': callKey,
                'sender': senderId,
                'device': deviceId,
                'txn_id': txnId,
                'generation_id': gen.id,
                'mxc_url': url.toString(),
                'event_id': eventId,
                'status': 'sent',
              });
            } catch (e, s) {
              Logs().w('Could not persist the call-audio sent state', e, s);
            }
            return;
          } on _AudioRecordingCanceled {
            // Fires for cancellation winning EITHER race above -- the
            // upload's or the send's; either way [gen.sent] was never set,
            // so the exit-guard above already knows whether this leaves an
            // orphan behind.
            _logAbandonment('ownership was lost while it was in flight');
            return;
          } catch (e, s) {
            lastError = e;
            lastStack = s;
            Logs().w(
              'Call audio half delivery attempt ${attempt + 1} of '
              '$deliveryAttempts failed',
              e,
              s,
            );
          }
        }

        // Every attempt failed. Reported, not merely logged: a half that
        // never lands makes this speaker read as absent from a call they
        // were recording, and only this device can say that happened --
        // see `CallRecord._publishTranscript`'s identical reasoning for the
        // transcript half. [gen.sent] is still false here by construction
        // (the loop only exits normally when every attempt has thrown), so
        // the exit-guard above will name the orphan too, if the upload
        // itself is what succeeded before the send kept failing.
        Logs().e(
          'Gave up sending this call\'s audio half after $deliveryAttempts '
          'attempts; it is lost',
        );
        await ErrorHandler.logErrorOnce(
          key: '$_giveUpKey:$callKey',
          e: lastError ?? Exception('This call\'s audio half was never sent'),
          s: lastStack,
          data: {
            'bytes': wav.length,
            'durationMs': durationMs,
            'sampleRate': gen.sampleRate,
            'channels': gen.channels,
          },
        );
      } finally {
        if (identical(_cancelSignal, cancelSignal)) _cancelSignal = null;
      }
    } finally {
      // The single enforcement point: whichever of the exits above this
      // method took -- an early cancellation, a mid-flight one, exhausting
      // every retry, or simply returning once sent -- this is the one place
      // downstream of every one of them. An orphan is exactly an upload
      // that landed ([gen.uploadedUrl] non-null) without [gen.sent] ever
      // becoming true; nothing else is trusted to have already reported it,
      // and nothing here needs to know WHICH exit path it was.
      final uploadedUrl = gen.uploadedUrl;
      if (uploadedUrl != null && !gen.sent) _logOrphan(gen, uploadedUrl);
    }
  }
}
