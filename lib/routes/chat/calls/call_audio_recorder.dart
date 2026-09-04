// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:matrix/matrix.dart';

// Project imports:
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
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
  /// begun -- on the same terms a `PcmChunker` run begins: a first frame, a
  /// stop-then-restart, a tap that died and was reattached, or a format
  /// change the chunker cannot carry across (a WAV file is fixed-format for
  /// its whole length, so a change map ends the container the same way a stop
  /// does). [runStartedAtMs] is the run's own start position -- exactly the
  /// value the transcript chunker was built from, never re-measured here, so
  /// the two consumers of one tap can never disagree about when a run began.
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

  /// The run [onRunStarted] opened has ended -- a stop, a mute, a tap death,
  /// or a format change. Mirrors `PcmChunker.flush()` timing exactly: called
  /// from the same place in [CallCaptureService] that flushes the transcript
  /// chunker, so the two consumers agree on where a run's audio ends.
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
  final ClockAnchor? clockAnchor;
  final int? offsetMs;

  _AudioGeneration({
    required this.sampleRate,
    required this.channels,
    required this.runStartedAtMs,
    required this.clockAnchor,
    required this.offsetMs,
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
  /// already dedups the EVENT server-side; this is what dedups the BLOB.
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

  /// Read FRESH each time a generation opens, never cached across the whole
  /// call: the anchor may not exist yet at construction (it is read off the
  /// SFU's join response, which can arrive after this recorder is built) and
  /// is not expected to change once it does.
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

  static const _defaultMaxBytes = 60 * 1024 * 1024;
  static const _defaultMaxDuration = Duration(minutes: 30);
  static const _defaultDeliveryAttempts = 3;
  static const _defaultRetryDelay = Duration(seconds: 1);

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
  }) : clockAnchor = clockAnchor ?? _noAnchor;

  static ClockAnchor? _noAnchor() => null;

  _AudioGeneration? _current;

  int _capBytes(_AudioGeneration gen) {
    final byTime =
        gen.sampleRate * gen.channels * 2 * maxDuration.inMilliseconds ~/ 1000;
    return maxBytes < byTime ? maxBytes : byTime;
  }

  @override
  void onRunStarted(int runStartedAtMs, int sampleRate, int channels) {
    // Superseded, not merely replaced: a [finish] already under way for the
    // OLD generation reads this flag before every network step it still has
    // to take, so a new run beginning here reliably stops a stale send even
    // when it lands mid-upload.
    _current?.canceled = true;
    final anchor = clockAnchor();
    _current = _AudioGeneration(
      sampleRate: sampleRate,
      channels: channels,
      runStartedAtMs: runStartedAtMs,
      clockAnchor: anchor,
      // A MONOTONIC delta, never a wall-clock subtraction: both readings come
      // off the SAME conversion `CallCaptureService._runStartsAt` already
      // uses for [runStartedAtMs] -- one wall-clock base taken once at the
      // call's first frame, refined by a monotonic counter for every run
      // after it -- so a device clock stepped mid-call cannot move this
      // number. See [CallAudioContent.recordingStartedOffsetFromDeviceJoinMs].
      offsetMs: anchor == null ? null : runStartedAtMs - anchor.deviceMs,
    );
  }

  @override
  void onFrame(Int16List samples) {
    final gen = _current;
    // Defensive rather than reachable: [CallCaptureService] never calls
    // [onFrame] without an [onRunStarted] before it in the same run. Dropped
    // silently because there is nothing sensible to attribute an orphaned
    // frame to, and this is not a failure the recording itself can report.
    if (gen == null || gen.canceled) return;
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

  @override
  void onRunEnded() {
    // Nothing to do here: the generation simply stops receiving frames until
    // either a new [onRunStarted] supersedes it, or [finish] uses it. Kept as
    // an explicit method (rather than folded away) because it is where a
    // future crash-safe upload would start flushing -- see the class-level
    // docs on what this prototype defers.
  }

  /// Callable by anything that later learns ownership was revoked out of
  /// band, before a fresh [onRunStarted] would otherwise notice it.
  /// [onRunStarted]'s own auto-supersede already exercises this same path
  /// automatically whenever a new stretch of carrying begins; this exists for
  /// the case where ownership is lost and never regained before the call
  /// ends, so nothing else would ever flip it.
  void cancelOwnership() => _current?.canceled = true;

  static const _giveUpKey = 'call_audio_recorder.upload_failed';

  @override
  Future<void> finish({
    required bool carriedOn,
    required String? callKey,
  }) async {
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

    // Read ONCE: the generation cannot grow after its run has ended, and
    // reading it fresh per attempt would cost nothing but a re-encode of
    // bytes that have not changed.
    final wav = pcm16ToWav(
      gen.takeBytes(),
      sampleRate: gen.sampleRate,
      channels: gen.channels,
    );
    final durationMs = gen.duration.inMilliseconds;

    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < deliveryAttempts; attempt++) {
      if (gen.canceled) {
        Logs().i(
          'Call audio half abandoned: ownership was lost while it was being '
          'sent',
        );
        return;
      }
      if (attempt > 0) await Future.delayed(retryDelay * attempt);
      try {
        // Reused across attempts: the deterministic transaction id below
        // already dedups the EVENT server-side, and this is what dedups the
        // BLOB -- a retry that only failed at the send step must not upload
        // the same recording a second time.
        var url = gen.uploadedUrl;
        url ??= await upload(
          wav,
          filename: 'call_audio.wav',
          contentType: 'audio/wav',
        );
        gen.uploadedUrl = url;

        // Checked AGAIN, immediately before the send: the upload above was
        // the one genuinely slow step, and ownership can have moved on while
        // it ran. "Abort upload if possible" is honoured as far as this
        // client can honour it -- nothing here can recall bytes already
        // handed to the homeserver -- but the EVENT, which is what makes the
        // blob findable and playable, is always still gatable, and this is
        // where that gate is.
        if (gen.canceled) {
          Logs().i(
            'Call audio half abandoned: ownership was lost before it could '
            'be sent',
          );
          return;
        }

        await writeCallAudioEvent(
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
          clockAnchor: gen.clockAnchor,
          recordingStartedOffsetFromDeviceJoinMs: gen.offsetMs,
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
  }
}
