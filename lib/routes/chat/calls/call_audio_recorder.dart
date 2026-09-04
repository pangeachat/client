// Dart imports:
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

// Package imports:
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

  /// The call is over. [carriedOn] is whether this device was still attached
  /// and running the instant the caller decided to stop capturing for
  /// good -- read once, before that decision could change it, so this is the
  /// one place this sink may trust the answer. [callKey] is the anchor the
  /// half relates to, read fresh because it may not have existed when this
  /// sink was built.
  ///
  /// THE gate. Nothing upstream of this may assume it has already excluded a
  /// non-carrying device -- see `CallCaptureService`'s own docs on where
  /// [carriedOn] comes from and why it cannot be derived any later than this.
  Future<void> finish({required bool carriedOn, required String? callKey});
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
  final int sampleRate;
  final int channels;
  final int runStartedAtMs;

  _AudioGeneration({
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
  Future<void> finish({required bool carriedOn, required String? callKey}) {
    return _finishing ??= _finish(
      carriedOn: carriedOn,
      callKey: callKey,
    ).whenComplete(() => _finishing = null);
  }

  Future<void> _finish({
    required bool carriedOn,
    required String? callKey,
  }) async {
    // Ahead of every guard below: a generation's bytes are not final until
    // every frame handed to [onFrame] has actually been applied to it, and
    // reading them one microtask early would ship a recording short of what
    // was truly captured.
    await _drainPending();

    final gen = _current;
    if (!carriedOn) {
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
    if (gen.canceled) {
      Logs().i(
        'No call audio half sent: the recording generation was superseded '
        'before it could be sent',
      );
      return;
    }
    if (callKey == null || callKey.isEmpty) {
      Logs().w('No call audio half sent: the call has no anchor to relate to');
      return;
    }

    final txnId = CallAudioContent.txnId(callKey, senderId, deviceId);

    // Best-effort: a store that cannot be read is treated as empty, never as
    // a reason to refuse sending a recording this device actually holds.
    Map<String, dynamic>? persisted;
    try {
      persisted = await uploadStateStore.read(txnId);
    } catch (e, s) {
      Logs().w('Could not read the persisted call-audio upload state', e, s);
    }
    if (persisted?['status'] == 'sent') {
      // Already landed on an earlier attempt -- possibly in a process that
      // has since restarted -- and the deterministic transaction id means a
      // resend would only collapse server-side anyway. Skipped here instead
      // to save the upload's own bytes leaving the device a second time.
      Logs().i(
        'No call audio half sent: this call\'s half was already sent '
        '(persisted state)',
      );
      return;
    }
    final persistedUrl = persisted?['mxc_url'];
    if (persistedUrl is String) {
      final parsed = Uri.tryParse(persistedUrl);
      // Validated, not merely parsed: `Uri.tryParse` accepts an empty string
      // and any relative one without complaint, and a persisted record this
      // reader cannot vouch for -- corrupted on disk, or written by some
      // future version of this code in a different shape -- must read as NO
      // url rather than as a real one. An event sent with a garbage `url`
      // field is a half nobody can play, which is worse than the wasted
      // upload a false negative here costs at most.
      if (parsed != null && parsed.scheme == 'mxc' && parsed.host.isNotEmpty) {
        gen.uploadedUrl = parsed;
      }
    }

    // Read HERE, once, from the SAME source and at the SAME point in the
    // call's life the transcript half reads its own `media.clockAnchor` --
    // see [clockAnchor]'s own docs for why an earlier version reading this
    // at [onRunStarted] could leave the two halves disagreeing about whether
    // an anchor existed at all.
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
          Logs().i(
            'Call audio half abandoned: ownership was lost while it was '
            'being sent',
          );
          return;
        }
        if (attempt > 0) await Future.delayed(retryDelay * attempt);
        // Checked AGAIN, immediately after the backoff: the delay above is
        // real time the recorder is not otherwise watching, and ownership
        // can be lost during it just as easily as during the upload itself.
        // Without this, a cached [gen.uploadedUrl] from an earlier attempt
        // would skip straight to the send-time check further down -- fine
        // on its own -- but a NOT-yet-uploaded generation would still
        // INITIATE a fresh upload attempt below before the race inside it
        // ever got a chance to notice a cancellation that had already
        // happened.
        if (gen.canceled) {
          Logs().i(
            'Call audio half abandoned: ownership was lost while this '
            'attempt was waiting to retry',
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
            // uploading is the one genuinely slow step, and "abort the
            // upload if possible" is honoured as far as this client can
            // honour it -- nothing here can recall bytes already handed to
            // the homeserver (see `CallUploadGate`'s own docs: this app's
            // HTTP layer has no request-level cancellation at all) -- but
            // there is no reason to go on WAITING for, or USING, an answer
            // that has stopped mattering. `Future.any` returns the moment
            // either side settles; the loser is simply never awaited again.
            url = await Future.any<Uri>([
              upload(wav, filename: 'call_audio.wav', contentType: 'audio/wav'),
              cancelSignal.future.then(
                (_) => throw const _AudioRecordingCanceled(),
              ),
            ]);
            // In memory FIRST, and deliberately not made to depend on the
            // durable write below succeeding: [gen.uploadedUrl] is what THIS
            // attempt's own retries key off, and the upload already
            // genuinely happened -- refusing to use it because an optional
            // local write hiccuped would throw away a real recording over a
            // failure that has nothing to do with whether it landed. A
            // failed write here costs only the CROSS-RESTART case
            // [CallAudioUploadStateStore] exists for, on the exact terms the
            // class-level docs already accept for a crash generally: logged,
            // not fatal.
            gen.uploadedUrl = url;
            try {
              await uploadStateStore.write(txnId, {
                'call_key': callKey,
                'sender': senderId,
                'device': deviceId,
                'txn_id': txnId,
                'mxc_url': url.toString(),
                'status': 'uploaded',
              });
            } catch (e, s) {
              Logs().w('Could not persist the call-audio upload state', e, s);
            }
          }

          // Checked AGAIN, immediately before the send: the step above was
          // the one genuinely slow one, and ownership can have moved on
          // while it ran.
          if (gen.canceled) {
            Logs().i(
              'Call audio half abandoned: ownership was lost before it '
              'could be sent',
            );
            return;
          }

          final eventId = await writeCallAudioEvent(
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
          );
          try {
            await uploadStateStore.write(txnId, {
              'call_key': callKey,
              'sender': senderId,
              'device': deviceId,
              'txn_id': txnId,
              'mxc_url': url.toString(),
              'event_id': ?eventId,
              'status': 'sent',
            });
          } catch (e, s) {
            Logs().w('Could not persist the call-audio sent state', e, s);
          }
          return;
        } on _AudioRecordingCanceled {
          Logs().i(
            'Call audio upload abandoned: ownership was lost while it was '
            'in flight',
          );
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

      // Every attempt failed. Reported, not merely logged: a half that never
      // lands makes this speaker read as absent from a call they were
      // recording, and only this device can say that happened -- see
      // `CallRecord._publishTranscript`'s identical reasoning for the
      // transcript half.
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
  }
}
