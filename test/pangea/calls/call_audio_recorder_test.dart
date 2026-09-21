import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show SynchronousFuture;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Logs;

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_recorder.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart'
    show ChunkTranscriber;
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import '../sentry_capture_harness.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart'
    show SpeechToTextResponseModel;
import 'call_transcript_sink_test.dart' show silent, spokenWord;

/// A one-word STT response whose word carries the given (possibly out-of-piece)
/// timing -- to exercise the piece-relative bounds in the chunked path.
SpeechToTextResponseModel _wordAt(String word, int startMs, int endMs) =>
    SpeechToTextResponseModel.fromJson({
      'results': [
        {
          'transcripts': [
            {
              'transcript': word,
              'confidence': 100,
              'lang_code': 'en-US',
              'words_per_hr': 9391,
              'word_timings': [
                {
                  'word': word,
                  'start_time_ms': startMs,
                  'end_time_ms': endMs,
                  'confidence': 100,
                },
              ],
              'stt_tokens': const [],
            },
          ],
        },
      ],
    });

const _callKey = '\$membership:example.com';
const _sender = '@alice:example.com';
const _device = 'DEVICEA';

/// A store whose `read`/`write` resolve on the SAME microtask turn rather
/// than deferring by one, the way every real `async` implementation
/// (including [InMemoryCallAudioUploadStateStore]) unavoidably does.
///
/// Used by exactly one test: the drain-race one below. `_drainPending`'s own
/// race is real, but `finish()` reads the persisted store immediately
/// afterwards -- and awaiting a NORMAL `async` function, even one with no
/// work of its own, still costs a microtask turn in Dart. That one extra
/// turn is enough time for a background pump to catch up on its own, which
/// makes the drain race pass whether or not `_drainPending` actually
/// re-checks -- a false mutation-proof. `SynchronousFuture` (from
/// `package:flutter/foundation.dart`, built for exactly this: skipping a
/// deferred frame) removes that incidental extra turn so the race the test
/// means to pin is the only one left to explain the result.
class _SameTurnStore implements CallAudioUploadStateStore {
  @override
  Future<Map<String, dynamic>?> read(String txnId) => SynchronousFuture(null);

  @override
  Future<void> write(String txnId, Map<String, dynamic> state) =>
      SynchronousFuture(null);
}

/// A store whose `write` blocks on [gate], so a test can land an action
/// (like cancelling ownership) precisely inside the window between the
/// upload succeeding (`gen.uploadedUrl` already set) and the persisted
/// 'uploaded' record actually landing -- which is otherwise too narrow a
/// window to reach with `pumpEventQueue()` alone, since nothing else
/// suspends there.
class _GatedWriteStore implements CallAudioUploadStateStore {
  _GatedWriteStore(this.gate);
  final Future<void> gate;

  @override
  Future<Map<String, dynamic>?> read(String txnId) async => null;

  @override
  Future<void> write(String txnId, Map<String, dynamic> state) => gate;
}

/// A store whose `read` blocks on [gate], so a test can land an action
/// (like cancelling ownership) precisely inside the window between
/// `finish()` starting and it discovering a persisted, already-uploaded
/// record for THIS generation -- otherwise too narrow a window to reach
/// with `pumpEventQueue()` alone, since nothing else suspends there.
///
/// [record] is mutable rather than a constructor argument: the record has
/// to be keyed to this generation's own real id (minted timestamp-plus-
/// random, never predictable -- see [CallAudioRecorder.currentGenerationId]'s
/// own docs), which is only known AFTER `onRunStarted` runs, but the store
/// itself has to exist before that, to be handed to the recorder's
/// constructor.
class _GatedReadStore implements CallAudioUploadStateStore {
  _GatedReadStore(this.gate);
  final Future<void> gate;
  Map<String, dynamic>? record;

  @override
  Future<Map<String, dynamic>?> read(String txnId) async {
    await gate;
    return record;
  }

  @override
  Future<void> write(String txnId, Map<String, dynamic> state) async {}
}

/// A store whose `read` models real persisted-state I/O latency by advancing
/// the injected monotonic clock by [byMs] while `finish()` is between draining
/// its queue and running the finalize reconcile. If the reconcile anchored to a
/// FRESH clock read taken at that point (the bug finding 1 fixes) rather than to
/// the audio-stop instant, those advanced milliseconds would be padded onto the
/// recording as trailing silence -- exactly what this store makes observable.
class _ClockAdvancingReadStore implements CallAudioUploadStateStore {
  _ClockAdvancingReadStore(this._clock, {required this.byMs});
  final _Clock _clock;
  final int byMs;

  @override
  Future<Map<String, dynamic>?> read(String txnId) async {
    _clock.pass(byMs);
    return null;
  }

  @override
  Future<void> write(String txnId, Map<String, dynamic> state) async {}
}

/// A [Timer] that never fires and no-ops on cancel. Injected as the recorder's
/// periodic-timer factory so a deterministic timing test can configure a real,
/// non-zero re-anchor interval -- which is what sizes the bounded micro-trim
/// budget ([CallAudioRecorder.maxReanchorTrimFrames]) -- WITHOUT a real
/// wall-clock [Timer.periodic] that could fire and reconcile on its own,
/// racing the test's manually driven [CallAudioRecorder.checkpoint]. With this
/// no real timer is created at all, so the only reconcile the file ever sees is
/// the one the test drove.
class _InertTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

/// [n] frames of [samplesPerFrame] mono 16-bit samples, all equal to [value]
/// -- a fixed tone (or, at value 0, digital silence) cheap to assert on.
Int16List _tone(int samplesPerFrame, {int value = 1000}) =>
    Int16List.fromList(List.filled(samplesPerFrame, value));

/// [samplesPerFrame] mono 16-bit samples whose value ENCODES their position:
/// sample j holds `start + j`. Fed with `start` set to a frame's absolute
/// offset, this builds one globally-monotone ramp across the whole file, so a
/// removed or shifted INTERIOR sample shows up as a discontinuity that a
/// uniform tone would hide -- the difference between proving a trim was
/// tail-only and merely proving the right COUNT was removed. All values stay
/// well inside the signed-16-bit range for the sizes these tests use.
Int16List _ramp(int samplesPerFrame, {required int start}) =>
    Int16List.fromList(List.generate(samplesPerFrame, (j) => start + j));

/// A hand-driven monotonic clock, mirroring the two-clock fake in
/// `call_capture_test.dart` but with only the monotonic hand the recorder's
/// write cursor reads. [pass] moves time forward the way real elapsed time
/// does; [elapsed] can be assigned directly to model a backward step (the one
/// case the drop guard exists for). Every recorder timing test drives THIS,
/// never real wall time, so results are deterministic.
class _Clock {
  int elapsed = 0;
  int monotonic() => elapsed;
  void pass(int by) => elapsed += by;
}

/// Reads the PCM16 sample at frame index [i] out of an uploaded WAV, skipping
/// the 44-byte canonical header (see `wav_writer.dart`). Mono only -- the
/// recorder tests all record one channel.
int _wavSampleAt(Uint8List wav, int i) =>
    ByteData.sublistView(wav, 44).getInt16(i * 2, Endian.little);

/// The number of PCM16 mono sample frames in an uploaded WAV.
int _wavSampleCount(Uint8List wav) => (wav.length - 44) ~/ 2;

void main() {
  late List<({Uint8List bytes, String filename, String contentType})> uploads;
  late Uri Function(Uint8List) uploadResult;
  late Completer<Uri>? uploadGate;
  late List<Map<String, dynamic>> sent;
  late List<String> txnIds;
  late int sendFailuresLeft;
  late Object? sendError;
  late int uploadFailuresLeft;
  late Completer<String?>? sendGate;

  CallAudioRecorder recorder({
    ClockAnchor? Function()? clockAnchor,
    int maxBytes = 60 * 1024 * 1024,
    Duration maxDuration = const Duration(minutes: 30),
    Duration retryDelay = Duration.zero,
    CallAudioUploadStateStore? uploadStateStore,
    int maxPendingFrames = 64,
    // The recording-based-transcript wiring. Left null in every existing test
    // (feature off), so the recorder never transcribes and those tests are
    // unchanged; the transcription group below wires a stub.
    ChunkTranscriber? transcribe,
    String? userL1,
    String? userL2,
    // The STT piece cap. Defaults to production (7MB); the multi-piece tests
    // shrink it so a short recording splits into several STT requests.
    int sttPieceBytes = 7000000,
    // The SOLE clock chokepoint. Defaulting to a NON-ADVANCING fake is what
    // keeps every existing frame-driven test (the size cap, the fan-out bound,
    // the drain race, the unhurried-capture duration) green with no per-test
    // edit and no loosened assertion: with elapsed pinned at 0 the cursor never
    // backfills silence and the finalize reconcile is a no-op, so duration is
    // exactly the frame-summed value it always was. Only the new timing tests
    // inject an advancing clock.
    int Function()? elapsedMs,
    // Disables the real wall-clock self-tick timer (tests drive `checkpoint()`
    // explicitly) AND, being zero, the bounded micro-trim -- so the finalize
    // reconcile only ever pads under a flat clock, never trims. A timing test
    // that needs the trim bound passes a real interval AND an inert timer
    // factory (see `periodicTimerFactory`), so the real budget is configured
    // without a real wall-clock timer to race.
    Duration reanchorInterval = Duration.zero,
    // Substitutes the periodic self-tick timer. Left null in every frame-driven
    // test (they use a zero interval, so no timer is armed anyway); the
    // micro-trim timing test injects an [_InertTimer] factory so its real,
    // non-zero interval sizes the drift budget without arming a real
    // `Timer.periodic` that could fire mid-test and race `checkpoint()`.
    Timer Function(Duration, void Function())? periodicTimerFactory,
  }) => CallAudioRecorder(
    senderId: _sender,
    deviceId: _device,
    clockAnchor: clockAnchor,
    elapsedMs: elapsedMs ?? () => 0,
    maxBytes: maxBytes,
    maxDuration: maxDuration,
    retryDelay: retryDelay,
    uploadStateStore: uploadStateStore,
    maxPendingFrames: maxPendingFrames,
    reanchorInterval: reanchorInterval,
    periodicTimerFactory: periodicTimerFactory,
    transcribe: transcribe,
    userL1: userL1,
    userL2: userL2,
    maxSttPieceBytes: sttPieceBytes,
    upload: (bytes, {required filename, required contentType}) async {
      uploads.add((bytes: bytes, filename: filename, contentType: contentType));
      if (uploadFailuresLeft > 0) {
        uploadFailuresLeft--;
        throw StateError('transient upload failure');
      }
      final gate = uploadGate;
      if (gate != null) return gate.future;
      return uploadResult(bytes);
    },
    send: (content, txnId) async {
      txnIds.add(txnId);
      if (sendFailuresLeft > 0) {
        sendFailuresLeft--;
        throw sendError ?? StateError('transient send failure');
      }
      // Recorded HERE, before any gate: this fake stands in for the actual
      // network call, which -- exactly like the upload -- has no
      // cancellation contract, so the bytes can be considered "sent" the
      // moment this is reached, whether or not the recorder's own code
      // ever learns the outcome.
      sent.add(content);
      final gate = sendGate;
      if (gate != null) return gate.future;
      return '\$event${sent.length}:example.com';
    },
  );

  setUp(() {
    uploads = [];
    uploadResult = (_) => Uri.parse('mxc://example.com/uploaded');
    uploadGate = null;
    sent = [];
    txnIds = [];
    sendFailuresLeft = 0;
    sendError = null;
    uploadFailuresLeft = 0;
    sendGate = null;
  });

  group('ownership gates the send', () {
    test('a device that never carried the recording sends nothing', () async {
      final r = recorder();
      // No onRunStarted / onFrame at all: this device never recorded.
      await r.finish(wasCarrier: false, callKey: _callKey);
      expect(uploads, isEmpty);
      expect(sent, isEmpty);
    });

    test(
      'a device that recorded but was not carrying at the end sends nothing',
      () async {
        final r = recorder();
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        // wasCarrier is read once, at the moment the caller decided to stop
        // for good -- false here means a sibling was the last one recording.
        await r.finish(wasCarrier: false, callKey: _callKey);
        expect(uploads, isEmpty);
        expect(sent, isEmpty);
      },
    );

    test(
      'a device that never opened a generation sends nothing even when wasCarrier',
      () async {
        final r = recorder();
        await r.finish(wasCarrier: true, callKey: _callKey);
        expect(uploads, isEmpty);
        expect(sent, isEmpty);
      },
    );

    test(
      'a carrying device with real audio uploads and sends exactly once',
      () async {
        final r = recorder();
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);
        expect(uploads, hasLength(1));
        expect(sent, hasLength(1));
        expect(sent.single['call_key'], _callKey);
        expect(sent.single['url'], 'mxc://example.com/uploaded');
      },
    );

    test(
      'a device whose generation was explicitly canceled sends nothing',
      () async {
        final r = recorder();
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        r.cancelOwnership();
        await r.finish(wasCarrier: true, callKey: _callKey);
        expect(uploads, isEmpty);
        expect(sent, isEmpty);
      },
    );

    test(
      'a NEW generation superseding the old one cancels it, even mid-upload',
      () async {
        final r = recorder();
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();

        uploadGate = Completer<Uri>();
        final finishing = r.finish(wasCarrier: true, callKey: _callKey);

        // Let `finish()` run all the way up to the point it is genuinely
        // blocked on the upload gate -- draining its own queued frame and
        // calling `upload()` both now cross a microtask boundary of their
        // own, so the OLD synchronous-prefix assumption ("finish() has
        // already read `_current` by the time this line runs") no longer
        // holds without pumping first.
        await pumpEventQueue();
        expect(uploads, hasLength(1), reason: 'the first upload has started');

        // Ownership moves on WHILE the upload for the first generation is
        // still in flight -- the exact race invariant 1 names: a device that
        // loses ownership mid-upload sends no EVENT for the stale generation.
        // The blob itself is a different guarantee (see
        // CallAudioRecorder's own class docs, "no request-level abort"): the
        // upload below is still allowed to land, as an accepted, logged
        // orphan -- what this test actually pins is that it is never USED.
        r.onRunStarted(5000, 16000, 1);
        r.onFrame(_tone(160));

        // Let the FIRST upload finally answer too. Win or lose the race
        // against the cancellation above, its result must never be used.
        uploadGate!.complete(Uri.parse('mxc://example.com/stale'));
        await finishing;

        expect(
          sent,
          isEmpty,
          reason: 'the superseded generation must never be sent',
        );
        expect(
          uploads,
          hasLength(1),
          reason: 'the upload was attempted but its result must be discarded',
        );
      },
    );
  });

  group('keying and idempotency', () {
    test(
      'a resend reuses the already-uploaded blob and the deterministic txnId',
      () async {
        sendFailuresLeft = 1;
        final r = recorder();
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        expect(
          uploads,
          hasLength(1),
          reason: 'the retry must not re-upload the same bytes',
        );
        expect(sent, hasLength(1));
        expect(
          txnIds,
          hasLength(2),
          reason: 'one failed attempt, one that landed',
        );
        expect(
          txnIds.toSet(),
          hasLength(1),
          reason: 'every attempt carries the SAME transaction id',
        );
        expect(
          txnIds.first,
          CallAudioContent.txnId(_callKey, _sender, _device),
        );
      },
    );
  });

  group('no silent failures', () {
    test(
      'giving up after every attempt reports once and does not throw',
      () async {
        final harness = SentryCaptureHarness();
        await harness.init();
        addTearDown(harness.close);

        sendFailuresLeft = 1 << 30; // never succeeds
        final r = recorder(retryDelay: Duration.zero);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();

        await harness.capture(() {
          expect(r.finish(wasCarrier: true, callKey: _callKey), completes);
        });
        expect(harness.events, hasLength(1));
      },
    );
  });

  group('alignment', () {
    test(
      'the offset is the monotonic delta from the device join reading',
      () async {
        final r = recorder(
          clockAnchor: () =>
              const ClockAnchor(sfuMs: 1_000_000, deviceMs: 1_000_050),
        );
        r.onRunStarted(1_000_300, 16000, 1); // 250ms after the device joined
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        final content = CallAudioContent.fromJson(sent.single)!;
        expect(content.recordingStartedOffsetFromDeviceJoinMs, 250);
        expect(
          content.clockAnchor,
          const ClockAnchor(sfuMs: 1_000_000, deviceMs: 1_000_050),
        );
        // file_start_sfu_ms = sfu_joined_at_ms + offset.
        expect(content.fileStartSfuMs, 1_000_250);
      },
    );

    test(
      'carries no alignment at all when no anchor was available at run start',
      () async {
        final r = recorder(clockAnchor: () => null);
        r.onRunStarted(1_000_300, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        final content = CallAudioContent.fromJson(sent.single)!;
        expect(content.clockAnchor, isNull);
        expect(content.recordingStartedOffsetFromDeviceJoinMs, isNull);
        expect(content.fileStartSfuMs, isNull);
      },
    );
  });

  group('the size cap', () {
    test(
      'stops growing the recording past the cap rather than growing it unbounded',
      () async {
        // 16kHz mono 16-bit: 32000 bytes/second. Cap at 1 second's worth.
        final r = recorder(
          maxBytes: 32000,
          maxDuration: const Duration(minutes: 30),
        );
        r.onRunStarted(0, 16000, 1);
        // Two one-second frames; the second should be dropped by the cap.
        r.onFrame(_tone(16000));
        r.onFrame(_tone(16000));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        final content = CallAudioContent.fromJson(sent.single)!;
        expect(content.size, lessThanOrEqualTo(32000 + 44));
        expect(content.durationMs, lessThanOrEqualTo(1000));
      },
    );

    test('a ceiling-cut half is written with truncated: true', () async {
      // Same fixture as above: the cap genuinely forces a drop (two
      // one-second frames against a one-second cap), which is the ONE
      // thing `truncated` is meant to mean -- not merely "this half is
      // long".
      final r = recorder(
        maxBytes: 32000,
        maxDuration: const Duration(minutes: 30),
      );
      r.onRunStarted(0, 16000, 1);
      r.onFrame(_tone(16000));
      r.onFrame(_tone(16000));
      r.onRunEnded();
      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      expect(content.truncated, isTrue);
    });

    test(
      'a half that never reached the cap is written with truncated: false',
      () async {
        // Comfortably under both the byte and duration ceilings -- the cap
        // never fires, so `cappedLogged` never latches.
        final r = recorder(
          maxBytes: 60 * 1024 * 1024,
          maxDuration: const Duration(minutes: 30),
        );
        r.onRunStarted(0, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        final content = CallAudioContent.fromJson(sent.single)!;
        expect(content.truncated, isFalse);
      },
    );
  });

  group('aborting a stale upload rather than waiting on it', () {
    test('finish() does not hang on an upload that will never resolve, once '
        'ownership is lost', () async {
      final r = recorder();
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      uploadGate = Completer<Uri>(); // deliberately never completed
      final finishing = r.finish(wasCarrier: true, callKey: _callKey);
      await pumpEventQueue();
      expect(uploads, hasLength(1), reason: 'the upload has started');

      r.cancelOwnership();

      // If `finish()` merely awaited the upload and checked `canceled`
      // afterwards, this would hang forever -- the gate is never
      // completed. Racing the cancellation is what lets it return anyway.
      await expectLater(
        finishing.timeout(const Duration(seconds: 2)),
        completes,
      );
      expect(sent, isEmpty);
    });

    test(
      'cancellation during the retry backoff stops a needless second upload',
      () async {
        // Attempt 0's upload fails outright, so `gen.uploadedUrl` is still
        // null going into attempt 1's backoff -- the one case where the
        // upload/cancel race alone cannot help, because there is no upload
        // in flight yet to race against.
        uploadFailuresLeft = 1;
        final r = recorder(retryDelay: const Duration(milliseconds: 200));
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();

        final finishing = r.finish(wasCarrier: true, callKey: _callKey);
        // Real time, deliberately: attempt 0 has failed and attempt 1 is now
        // inside its 200ms backoff.
        await Future.delayed(const Duration(milliseconds: 50));
        expect(uploads, hasLength(1), reason: 'attempt 0 already failed once');

        r.cancelOwnership();

        await finishing;
        expect(
          uploads,
          hasLength(1),
          reason:
              'the check right after the backoff must stop a second upload '
              'from ever starting',
        );
        expect(sent, isEmpty);
      },
    );
  });

  group('the orphan blob is traced, not silently dropped', () {
    test('a blob that lands AFTER cancellation is logged with its url (the '
        'upload-future observer)', () async {
      final logsBefore = Logs().outputEvents.length;
      final r = recorder();
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      uploadGate = Completer<Uri>();
      final finishing = r.finish(wasCarrier: true, callKey: _callKey);
      await pumpEventQueue();
      expect(uploads, hasLength(1));

      r.cancelOwnership();
      uploadGate!.complete(Uri.parse('mxc://example.com/orphan-a'));
      await finishing;
      // The observer is deliberately `unawaited` in production -- `finish()`
      // must not block on the very future it just gave up waiting for --
      // so it can settle on its own microtask turn AFTER `finishing`
      // already resolved. Pumped once more here so the test observes it.
      await pumpEventQueue();

      expect(sent, isEmpty);
      final newLogs = Logs().outputEvents.skip(logsBefore);
      expect(
        newLogs.any((e) => e.title.contains('mxc://example.com/orphan-a')),
        isTrue,
        reason:
            'the orphan\'s actual url must be traceable in the logs, not '
            'folded into a generic "abandoned" message',
      );
    });

    test('a blob that landed BEFORE cancellation is ALSO logged with its url '
        '(the pre-send check)', () async {
      // The gap the first test above does not cover: here the upload has
      // already fully succeeded -- `gen.uploadedUrl` is set, nothing is
      // racing anything -- and cancellation is only noticed at the
      // separate "checked again immediately before send" guard. That
      // guard used to log a generic "abandoned" message with no url.
      final logsBefore = Logs().outputEvents.length;
      final writeGate = Completer<void>();
      final store = _GatedWriteStore(writeGate.future);
      uploadResult = (_) => Uri.parse('mxc://example.com/orphan-b');

      final r = recorder(uploadStateStore: store);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      final finishing = r.finish(wasCarrier: true, callKey: _callKey);
      // The upload itself resolves immediately (no gate); what blocks is
      // persisting it, which lands `finish()` exactly between "uploaded"
      // and the pre-send check.
      await pumpEventQueue();
      expect(uploads, hasLength(1), reason: 'the upload already landed');

      r.cancelOwnership();
      writeGate.complete();
      await finishing;

      expect(sent, isEmpty);
      final newLogs = Logs().outputEvents.skip(logsBefore);
      expect(
        newLogs.any((e) => e.title.contains('mxc://example.com/orphan-b')),
        isTrue,
        reason:
            'the orphan\'s actual url must be traceable here too, not '
            'just in the mid-upload case above',
      );
    });

    test('a blob already on record when finish() starts is still named if '
        'ownership is lost while it reads its own persisted state', () async {
      // The retry loop's OWN top-of-loop check cannot be pinned this way
      // from inside a single finish() run -- nothing separates one
      // attempt's failure from the next attempt's top-of-loop check (no
      // await sits between them for a test to land inside), so whatever
      // `gen.canceled` was at the first is exactly what it still is at
      // the second. But the SAME check also runs for attempt 0, and
      // there IS a real await ahead of that: the persisted-state read
      // finish() does before the loop ever starts. A record already
      // sitting there from an earlier, interrupted attempt exercises the
      // exact same line the loop's later attempts would.
      final readGate = Completer<void>();
      final store = _GatedReadStore(readGate.future);
      final r = recorder(uploadStateStore: store);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();
      store.record = {
        'status': 'uploaded',
        'mxc_url': 'mxc://example.com/orphan-e',
        'generation_id': r.currentGenerationId,
      };

      final logsBefore = Logs().outputEvents.length;
      final finishing = r.finish(wasCarrier: true, callKey: _callKey);
      await pumpEventQueue();

      r.cancelOwnership();
      readGate.complete();
      await finishing;

      expect(uploads, isEmpty, reason: 'the persisted url must be reused');
      expect(sent, isEmpty);
      final newLogs = Logs().outputEvents.skip(logsBefore);
      expect(
        newLogs.any((e) => e.title.contains('mxc://example.com/orphan-e')),
        isTrue,
        reason:
            'the very first cancellation check inside the loop must name '
            'the orphan too, not just the checks later in it',
      );
    });

    test(
      'a blob uploaded on an earlier, exhausted finish() call is named by '
      'the give-up path itself, and the SAME orphan is never logged twice',
      () async {
        // A realistic sequel to a give-up, not a contrived one:
        // `CallRecord.finish()` -- see `_finishing`'s own docs -- can
        // legitimately call [finish] twice for the same call ("a hangup
        // and a disconnect routinely arrive together"). If the FIRST call
        // uploads successfully but exhausts every delivery attempt on the
        // SEND (a real failure, not cancellation) and gives up, the url it
        // left on `gen` sits there for whichever call notices ownership is
        // gone next -- including a SECOND call that never reaches the
        // retry loop at all, because the check outside the loop catches it
        // first. That second call reaches the SAME exit-guard with the
        // SAME uploadedUrl still set and sent still false, so without a
        // latch it would re-report the identical orphan a second time.
        uploadResult = (_) => Uri.parse('mxc://example.com/orphan-g');
        sendFailuresLeft = 3; // exhausts all 3 default delivery attempts
        final r = recorder(retryDelay: Duration.zero);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();

        // Captured BEFORE the first call, not after: the exit-guard fires
        // on EVERY finish() invocation that leaves an upload un-sent,
        // including a SECOND one -- so capturing this after the first call
        // would let a second call's own pre-loop check cover for a broken
        // give-up path, since it reaches the very same exit-guard and
        // would still find the same orphan. That gap is exactly what let
        // this test pass a cold gate while the give-up path itself
        // bypassed the exit-guard entirely.
        final logsBeforeFirstCall = Logs().outputEvents.length;
        await r.finish(wasCarrier: true, callKey: _callKey);

        expect(uploads, hasLength(1), reason: 'the first call uploaded once');
        expect(sent, isEmpty, reason: 'every send attempt failed');
        final logsFromFirstCall = Logs().outputEvents
            .skip(logsBeforeFirstCall)
            .toList();
        expect(
          logsFromFirstCall
              .where((e) => e.title.contains('mxc://example.com/orphan-g'))
              .length,
          1,
          reason:
              'the give-up path itself must name the orphan exactly once '
              '-- true from the FIRST call alone, before a second call '
              'ever runs',
        );

        r.cancelOwnership();

        final logsBeforeSecondCall = Logs().outputEvents.length;
        await r.finish(wasCarrier: true, callKey: _callKey);

        expect(
          uploads,
          hasLength(1),
          reason: 'the second call must not upload a second time',
        );
        final logsFromSecondCall = Logs().outputEvents
            .skip(logsBeforeSecondCall)
            .toList();
        expect(
          logsFromSecondCall.any(
            (e) => e.title.contains(
              'the recording generation was superseded before it could be '
              'sent',
            ),
          ),
          isTrue,
          reason:
              'the pre-loop check a second call hits must still say why, '
              'even though the url-orphan guarantee no longer lives at '
              'this site',
        );
        expect(
          logsFromSecondCall
              .where((e) => e.title.contains('mxc://example.com/orphan-g'))
              .length,
          0,
          reason:
              'the latch must stop the SAME orphan being logged again '
              'just because a second finish() call also reaches the '
              'exit-guard with the same uploadedUrl still set and sent '
              'still false',
        );

        // Stated directly, spanning both calls together, not just proven
        // by the two windows above summing to it: the orphan url must
        // appear EXACTLY once across any number of sequential finish()
        // calls for this generation, however many of them re-discover the
        // same un-sent upload.
        final logsAcrossBothCalls = Logs().outputEvents
            .skip(logsBeforeFirstCall)
            .toList();
        expect(
          logsAcrossBothCalls
              .where((e) => e.title.contains('mxc://example.com/orphan-g'))
              .length,
          1,
          reason:
              'exactly one orphan-url log must exist across both calls '
              'combined',
        );
      },
    );

    test('a successful send does not log a false orphan', () async {
      final logsBefore = Logs().outputEvents.length;
      final r = recorder();
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      await r.finish(wasCarrier: true, callKey: _callKey);

      expect(uploads, hasLength(1));
      expect(sent, hasLength(1), reason: 'the send genuinely succeeded');
      final newLogs = Logs().outputEvents.skip(logsBefore);
      expect(
        newLogs.any((e) => e.title.contains('is now an orphan')),
        isFalse,
        reason:
            'gen.sent must suppress the exit-guard\'s own orphan log on '
            'the ordinary, successful path -- an upload that WAS '
            'durably sent is not an orphan',
      );
    });

    test('a blob uploaded before a retry backoff is named if ownership is '
        'lost during that wait', () async {
      // The mirror image of "cancellation during the retry backoff stops
      // a needless second upload" above: THERE, attempt 0's upload
      // itself fails, so gen.uploadedUrl is still null going into the
      // backoff. HERE, attempt 0's upload succeeds and its SEND fails
      // instead (a real error, not cancellation), so by the time attempt
      // 1's backoff begins there is a real blob on record for the
      // post-backoff check to name if ownership is lost during the wait.
      sendFailuresLeft = 1;
      uploadResult = (_) => Uri.parse('mxc://example.com/orphan-f');
      final r = recorder(retryDelay: const Duration(milliseconds: 200));
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      final logsBefore = Logs().outputEvents.length;
      final finishing = r.finish(wasCarrier: true, callKey: _callKey);
      // Real time, deliberately (mirrors the existing backoff test
      // above): attempt 0 has uploaded, its send has failed once, and
      // attempt 1 is now inside its 200ms backoff.
      await Future.delayed(const Duration(milliseconds: 50));
      expect(uploads, hasLength(1), reason: 'attempt 0 already uploaded');

      r.cancelOwnership();
      await finishing;

      expect(sent, isEmpty);
      final newLogs = Logs().outputEvents.skip(logsBefore);
      expect(
        newLogs.any((e) => e.title.contains('mxc://example.com/orphan-f')),
        isTrue,
        reason:
            'the post-backoff check must name the orphan uploaded on the '
            'earlier attempt, not just say "abandoned"',
      );
    });
  });

  group('cancel during the send itself', () {
    test('finish() does not hang on a send that will never resolve, once '
        'ownership is lost', () async {
      final r = recorder();
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      sendGate = Completer<String?>(); // never completed
      final finishing = r.finish(wasCarrier: true, callKey: _callKey);
      await pumpEventQueue();
      expect(
        uploads,
        hasLength(1),
        reason: 'the upload already landed by the time the send starts',
      );

      r.cancelOwnership();

      // If the send were merely awaited (not raced), this would hang --
      // the gate is never completed.
      await expectLater(
        finishing.timeout(const Duration(seconds: 2)),
        completes,
      );

      // The underlying network call is recorded by the fake the instant
      // it is reached (see the `send:` closure above) -- exactly the
      // "no cancellation contract" reality this test pins: the bytes may
      // well have reached the homeserver, even though this device gave up
      // waiting for confirmation.
      expect(txnIds, hasLength(1), reason: 'the send was genuinely attempted');
    });

    test('a cancellation that wins the send race leaves no persisted "sent" '
        'record, using the store the recorder actually writes to', () async {
      final store = InMemoryCallAudioUploadStateStore();
      final r = recorder(uploadStateStore: store);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      sendGate = Completer<String?>(); // never completed
      final finishing = r.finish(wasCarrier: true, callKey: _callKey);
      await pumpEventQueue();

      r.cancelOwnership();
      // Bounded, not a bare await: if the send were merely awaited rather
      // than raced, this would hang for the gate that never completes --
      // a slow, unclear timeout failure rather than a fast, clear one.
      await finishing.timeout(const Duration(seconds: 2));

      expect(
        txnIds,
        hasLength(1),
        reason: 'the send was raced, not skipped outright',
      );

      final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
      final persisted = await store.read(txnId);
      expect(
        persisted?['status'],
        isNot('sent'),
        reason:
            'a cancellation that wins the send race must never be '
            'persisted as a confirmed send',
      );
    });

    test('a cancellation that wins the send race logs the already-uploaded '
        'blob\'s url, not a generic message', () async {
      // The third and last orphan timing: the send race is only ever
      // entered once the upload has already landed (`gen.uploadedUrl` is
      // what the "checked again immediately before send" guard above the
      // send race depends on, and this test's own cancellation lands
      // AFTER that guard has already passed), so by the time this
      // cancellation wins the send race, the blob it orphans is sitting
      // right there in `gen.uploadedUrl`. The catch this falls into used
      // to log a single message shared with the OTHER thing that can win
      // this same exception type -- cancellation winning the UPLOAD race
      // instead, where there genuinely is no url yet -- so it could not
      // say which case this was.
      final logsBefore = Logs().outputEvents.length;
      uploadResult = (_) => Uri.parse('mxc://example.com/orphan-c');
      final r = recorder();
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      sendGate = Completer<String?>(); // never completed
      final finishing = r.finish(wasCarrier: true, callKey: _callKey);
      await pumpEventQueue();
      expect(
        uploads,
        hasLength(1),
        reason: 'the upload already landed by the time the send starts',
      );

      r.cancelOwnership();
      await finishing.timeout(const Duration(seconds: 2));

      final newLogs = Logs().outputEvents.skip(logsBefore);
      expect(
        newLogs.any((e) => e.title.contains('mxc://example.com/orphan-c')),
        isTrue,
        reason:
            'a cancellation that wins the send race must name the blob '
            'it orphans, exactly like the other two timings above',
      );
    });
  });

  group('the frame fan-out is bounded and non-blocking', () {
    test(
      'drops frames rather than growing without bound when it falls behind',
      () async {
        // A burst fed with no await in between, exactly how CallCaptureService
        // calls `onFrame` -- synchronously, from inside the platform tap's own
        // callback -- so nothing drains between calls until this test itself
        // yields.
        final r = recorder(maxPendingFrames: 8);
        r.onRunStarted(0, 16000, 1);
        final frame = _tone(1600); // 100ms @ 16kHz mono
        for (var i = 0; i < 40; i++) {
          r.onFrame(frame);
        }
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        final content = CallAudioContent.fromJson(sent.single)!;
        // At most the 8 that fit in the bound; the other 32 were dropped
        // rather than blocking the caller or growing the queue unboundedly.
        expect(content.durationMs, lessThanOrEqualTo(8 * 100));
        expect(content.durationMs, greaterThan(0));
      },
    );

    test(
      'a frame queued for a generation that is superseded before the pump '
      'runs is dropped, never credited to the generation that replaced it',
      () async {
        final r = recorder();
        r.onRunStarted(0, 16000, 1);
        // Queued for the FIRST generation, but nothing has drained yet.
        r.onFrame(_tone(1600));
        // Superseded before the queued frame above was ever applied.
        r.onRunStarted(5000, 16000, 1);
        r.onFrame(_tone(1600));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        final content = CallAudioContent.fromJson(sent.single)!;
        expect(
          content.durationMs,
          lessThanOrEqualTo(100),
          reason:
              'only the second generation\'s own frame may appear -- the '
              'first generation\'s queued frame must not be credited to it',
        );
      },
    );

    test('ordinary, unhurried capture is unaffected by the bound', () async {
      final r = recorder(maxPendingFrames: 8);
      r.onRunStarted(0, 16000, 1);
      for (var i = 0; i < 40; i++) {
        r.onFrame(_tone(1600));
        // Draining between frames, as real (non-bursty) capture does.
        await pumpEventQueue();
      }
      r.onRunEnded();
      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      expect(content.durationMs, 40 * 100);
    });
  });

  group('alignment is read at finish, not at run start', () {
    test('an anchor that only becomes available AFTER the run started is still '
        'used', () async {
      ClockAnchor? anchor; // not yet available when the run starts
      final r = recorder(clockAnchor: () => anchor);
      r.onRunStarted(1_000_300, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();

      // The SFU's join stamp arrives late -- a slow handshake, a
      // reconnect -- exactly as `media.clockAnchor` can for the transcript
      // half that reads the very same source.
      anchor = const ClockAnchor(sfuMs: 1_000_000, deviceMs: 1_000_050);

      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      expect(
        content.clockAnchor,
        const ClockAnchor(sfuMs: 1_000_000, deviceMs: 1_000_050),
        reason:
            'reading the anchor at finish -- the same moment the transcript '
            'half reads media.clockAnchor -- must not miss one that only '
            'became available after the recording started',
      );
      expect(content.recordingStartedOffsetFromDeviceJoinMs, 250);
    });
  });

  group('the drain race', () {
    test('a frame queued in the gap between the pump completing and finish() '
        'resuming is not lost', () async {
      // `_drainPending` completing does not resume `finish()` on the SAME
      // microtask turn -- Dart never runs a Future's continuation
      // synchronously with the call that completed it -- so a frame
      // queued in that one-turn gap is exactly the race `_drainPending`'s
      // own re-check loop exists to close. `_SameTurnStore` is what makes
      // the proof clean: see its own docs for why an ordinary store would
      // let this pass by accident.
      final r = recorder(uploadStateStore: _SameTurnStore());
      r.onRunStarted(0, 16000, 1);
      r.onFrame(_tone(1600)); // frame A: queued, not yet drained
      // Frame B lands as its own microtask, scheduled right behind
      // frame A's pump -- squarely in the gap `_drainPending`'s single
      // completer-await (rather than a loop) would miss.
      scheduleMicrotask(() => r.onFrame(_tone(1600)));

      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      expect(
        content.durationMs,
        200,
        reason:
            'both frames -- A and the one that arrived in the gap -- '
            'must be captured',
      );
    });
  });

  group('persisted upload state', () {
    test('a persisted "sent" status skips sending again entirely', () async {
      final store = InMemoryCallAudioUploadStateStore();
      final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
      await store.write(txnId, {
        'status': 'sent',
        'mxc_url': 'mxc://example.com/already-sent',
      });

      final r = recorder(uploadStateStore: store);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();
      await r.finish(wasCarrier: true, callKey: _callKey);

      expect(uploads, isEmpty);
      expect(sent, isEmpty);
    });

    test(
      'a persisted upload not yet confirmed sent is reused, never re-uploaded',
      () async {
        final store = InMemoryCallAudioUploadStateStore();
        final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
        final r = recorder(uploadStateStore: store);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        // Written with THIS generation's own real id: generation ids are
        // minted timestamp-plus-random (see [CallAudioRecorder._newGenerationId]),
        // never a predictable counter, so the only way to seed a record
        // this generation will recognise as its own is to read the id back
        // off it directly.
        await store.write(txnId, {
          'status': 'uploaded',
          'mxc_url': 'mxc://example.com/already-there',
          'generation_id': r.currentGenerationId,
        });

        await r.finish(wasCarrier: true, callKey: _callKey);

        expect(
          uploads,
          isEmpty,
          reason: 'the persisted url must be reused, not re-uploaded',
        );
        expect(sent, hasLength(1));
        expect(sent.single['url'], 'mxc://example.com/already-there');
      },
    );

    test(
      'a persisted upload from a DIFFERENT generation is never reused',
      () async {
        // The cold review's core finding: the store is keyed by [txnId],
        // which names the CALL and is identical across every generation of
        // it. Without a generation check, a generation that uploaded, was
        // persisted, and was then superseded before it could send would
        // have its stale url handed to whichever LATER generation happens
        // to run `finish()` next -- publishing an event whose audio and
        // whose metadata (duration, format, alignment) belong to two
        // different recordings.
        final store = InMemoryCallAudioUploadStateStore();
        final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
        await store.write(txnId, {
          'status': 'uploaded',
          'mxc_url': 'mxc://example.com/stale-generation',
          // A well-formed but arbitrary id: generation ids are minted
          // timestamp-plus-random, so this can never legitimately collide
          // with the fresh recorder's own generation below -- simulating
          // exactly the earlier, superseded generation's own leftover
          // record. See the RESTART test below for the specific shape of
          // collision an in-process counter used to produce.
          'generation_id': 'some-other-generations-id',
        });

        final r = recorder(uploadStateStore: store);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        expect(
          uploads,
          hasLength(1),
          reason: 'a different generation\'s persisted url must not be reused',
        );
        expect(sent, hasLength(1));
        expect(
          sent.single['url'],
          'mxc://example.com/uploaded',
          reason:
              'must be THIS generation\'s own fresh upload, never the '
              'stale one',
        );
      },
    );

    test('a persisted record from BEFORE A RESTART never collides with a '
        'fresh recorder\'s own generation, even though a naive in-process '
        'counter would have', () async {
      // The cold review's exact scenario: process 1's generation A
      // uploads and is persisted, then loses ownership before it can
      // send -- exactly the shape a mid-call restart leaves behind, a
      // persisted 'uploaded' record with no matching 'sent' one. A fresh
      // `CallAudioRecorder` -- "process 2" -- sharing the same durable
      // store must never be handed generation A's url, however it is
      // identified.
      final store = InMemoryCallAudioUploadStateStore();
      final txnId = CallAudioContent.txnId(_callKey, _sender, _device);

      final processOne = recorder(uploadStateStore: store);
      processOne.onRunStarted(1000, 16000, 1);
      processOne.onFrame(_tone(160));
      processOne.onRunEnded();
      final generationAId = processOne.currentGenerationId!;
      // A naive process-local counter (`0, 1, 2, ...`, reset by every
      // fresh recorder) would have minted this SAME value for process
      // one's own first generation -- which is exactly the collision
      // this test is pinned against, on process two's side below.
      expect(generationAId, isNot('0'), reason: 'sanity: not a bare counter');
      await store.write(txnId, {
        'status': 'uploaded',
        'mxc_url': 'mxc://example.com/generation-a',
        'generation_id': generationAId,
      });

      // "Process 2": a completely fresh recorder instance, as a restart
      // mid-call would produce -- sharing the durable store, but with
      // its own, independently-minted generation.
      final processTwo = recorder(uploadStateStore: store);
      processTwo.onRunStarted(5000, 16000, 1);
      processTwo.onFrame(_tone(160));
      processTwo.onRunEnded();
      final generationBId = processTwo.currentGenerationId!;

      expect(
        generationBId,
        isNot(generationAId),
        reason:
            'two independently-created recorders must never mint the '
            'same generation id',
      );

      await processTwo.finish(wasCarrier: true, callKey: _callKey);

      expect(
        uploads,
        hasLength(1),
        reason:
            'process two must upload its OWN bytes, never reuse process '
            'one\'s persisted (and by now stale/canceled) url',
      );
      expect(sent, hasLength(1));
      expect(sent.single['url'], 'mxc://example.com/uploaded');

      final afterProcessTwo = await store.read(txnId);
      expect(afterProcessTwo!['generation_id'], generationBId);
    });

    test(
      'a successful send persists enough for a future restart to find it',
      () async {
        final store = InMemoryCallAudioUploadStateStore();
        final r = recorder(uploadStateStore: store);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        final generationId = r.currentGenerationId;
        await r.finish(wasCarrier: true, callKey: _callKey);

        final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
        final persisted = await store.read(txnId);
        expect(persisted, isNotNull);
        expect(persisted!['status'], 'sent');
        expect(persisted['mxc_url'], 'mxc://example.com/uploaded');
        expect(persisted['event_id'], isNotNull);
        expect(persisted['call_key'], _callKey);
        expect(persisted['sender'], _sender);
        expect(persisted['device'], _device);
        expect(persisted['txn_id'], txnId);
        expect(persisted['generation_id'], generationId);
      },
    );

    test('a malformed persisted url is ignored rather than trusted', () async {
      // A cold review's finding: `Uri.tryParse` accepts an empty or
      // relative string without complaint, so a corrupted or
      // wrongly-shaped persisted record must not be trusted as a real
      // upload -- it would send an event whose url points nowhere.
      final store = InMemoryCallAudioUploadStateStore();
      final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
      final r = recorder(uploadStateStore: store);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();
      await store.write(txnId, {
        'status': 'uploaded',
        'mxc_url': 'not-a-valid-mxc-url',
        'generation_id': r.currentGenerationId,
      });

      await r.finish(wasCarrier: true, callKey: _callKey);

      expect(
        uploads,
        hasLength(1),
        reason: 'a garbage persisted url must not be trusted',
      );
      expect(sent, hasLength(1));
      expect(sent.single['url'], 'mxc://example.com/uploaded');
    });

    test(
      'a persisted mxc url with no media id is ignored rather than trusted',
      () async {
        // `mxc://server` alone -- scheme and host, no media-id path
        // segment -- parses cleanly and names nothing playable. Matrix's
        // own content-uri shape is `mxc://server/media-id`; a reference
        // missing the second half is exactly as untrustworthy as an empty
        // or malformed one.
        final store = InMemoryCallAudioUploadStateStore();
        final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
        final r = recorder(uploadStateStore: store);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await store.write(txnId, {
          'status': 'uploaded',
          'mxc_url': 'mxc://example.com',
          'generation_id': r.currentGenerationId,
        });

        await r.finish(wasCarrier: true, callKey: _callKey);

        expect(
          uploads,
          hasLength(1),
          reason: 'a media-id-less mxc url must not be trusted',
        );
        expect(sent, hasLength(1));
        expect(sent.single['url'], 'mxc://example.com/uploaded');
      },
    );

    test(
      'a null send result (a failed send) is retried, never marked sent',
      () async {
        // `Room.sendEvent` returns null EXACTLY when the send did not
        // durably succeed (see its own implementation) -- never as a
        // quieter kind of success. Marking `status: 'sent'` on a null
        // result would permanently drop a valid resend.
        final store = InMemoryCallAudioUploadStateStore();
        var sendCalls = 0;
        final r = CallAudioRecorder(
          senderId: _sender,
          deviceId: _device,
          uploadStateStore: store,
          retryDelay: Duration.zero,
          upload: (bytes, {required filename, required contentType}) async {
            uploads.add((
              bytes: bytes,
              filename: filename,
              contentType: contentType,
            ));
            return Uri.parse('mxc://example.com/uploaded');
          },
          send: (content, txnId) async {
            sendCalls++;
            if (sendCalls == 1) return null; // the homeserver's own failure
            sent.add(content);
            return '\$event:example.com';
          },
        );
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        expect(
          sendCalls,
          2,
          reason: 'the null result must count as a failure and be retried',
        );
        expect(sent, hasLength(1), reason: 'the retry lands');
        expect(
          uploads,
          hasLength(1),
          reason: 'the cached upload must not be repeated across the retry',
        );

        final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
        final persisted = await store.read(txnId);
        expect(persisted!['status'], 'sent');
      },
    );
  });

  group('two concurrent finish() calls', () {
    test(
      'join ONE execution, so cancellation reaches the race that matters',
      () async {
        // `CallRecord.finish()` -- the real caller -- is itself reachable
        // twice for one call ("a hangup and a disconnect routinely arrive
        // together"), with no guard against calling this a second time.
        // Two independent executions would each mint their own cancel
        // signal and each overwrite the other in `_cancelSignal`, so
        // `cancelOwnership()` could only ever wake ONE of them -- leaving
        // the other permanently blocked on an upload nothing would ever
        // tell it to give up on.
        final r = recorder();
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();

        uploadGate = Completer<Uri>(); // deliberately never completed
        final first = r.finish(wasCarrier: true, callKey: _callKey);
        final second = r.finish(wasCarrier: true, callKey: _callKey);
        await pumpEventQueue();
        expect(
          uploads,
          hasLength(1),
          reason: 'both calls must join ONE execution, not run two',
        );

        r.cancelOwnership();

        await expectLater(
          Future.wait([first, second]).timeout(const Duration(seconds: 2)),
          completes,
        );
        expect(sent, isEmpty);
      },
    );
  });

  group('continuous full-duration recording (the clock-driven cursor)', () {
    test('a muted stretch that delivers NO frames is still recorded as '
        'full-length silence, not truncated', () async {
      // THE BUG. On Android, muting disables the mic track so the native
      // post-AEC tap stops delivering frames entirely. A frame-driven recorder
      // simply stops advancing, so the blob is truncated at the mute (the real
      // call: 15s on the phone against 37.5s on the laptop). The clock-driven
      // cursor materialises the muted interval as silence of the right length
      // whether or not any frame arrives during it.
      final clock = _Clock();
      final r = recorder(elapsedMs: clock.monotonic);
      r.onRunStarted(1000, 16000, 1); // sample zero at elapsed 0
      r.onFrame(_tone(160)); // 10ms of real audio
      clock.pass(5000); // 5s muted -- NO frames arrive (the Android case)
      r.onFrame(_tone(160)); // one frame after unmute, at elapsed 5000
      clock.pass(20); // the call ends 20ms after that last frame arrived
      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      // Full length -- the 5s gap is present -- NOT the ~20ms two frames sum to.
      expect(content.durationMs, 5020);

      // Mutation-proof: decode the WAV and prove the muted interval is real
      // digital silence of the right length, not merely that the duration
      // number is large.
      final wav = uploads.single.bytes;
      expect(_wavSampleCount(wav), 5020 * 16); // 80320 mono frames @ 16kHz
      expect(_wavSampleAt(wav, 0), 1000, reason: 'the first real frame');
      for (var i = 160; i < 80000; i++) {
        // [10ms, 5000ms): the muted gap, every sample silent.
        if (_wavSampleAt(wav, i) != 0) {
          fail('sample $i in the muted range was not silent');
        }
      }
      expect(
        _wavSampleAt(wav, 80000),
        1000,
        reason: 'the real frame delivered after unmute is preserved',
      );
    });

    test('a run whose last frame is followed by silent time is padded to the '
        'end anchor at finalize', () async {
      // The pure-tail case, isolating the finalize reconcile from the
      // per-frame backfill: one frame, then 5s of elapsed time with nothing
      // more delivered and no unmute frame to trigger a catch-up. Finalize
      // alone must pad the file out to the elapsed end.
      final clock = _Clock();
      final r = recorder(elapsedMs: clock.monotonic);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160)); // 10ms of real audio at elapsed 0
      clock.pass(5000); // 5s elapses; the run is never fed another frame
      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      expect(content.durationMs, 5000);
      final wav = uploads.single.bytes;
      expect(_wavSampleAt(wav, 0), 1000, reason: 'the one real frame survives');
      for (var i = 160; i < 5000 * 16; i++) {
        if (_wavSampleAt(wav, i) != 0) {
          fail('the finalize pad at sample $i was not silent');
        }
      }
    });

    test('a file running AHEAD of elapsed is micro-trimmed by at most one '
        "interval's drift, never into interior audio", () async {
      // The "ahead" reconciliation: a fast capture clock leaves the tail real
      // samples with no silence to drop, so the checkpoint micro-trims -- but
      // by AT MOST one interval's drift, an imperceptible slice. Here the file
      // is driven far ahead (500ms of real audio while the clock stays at 0) to
      // prove the bound holds even when the overrun dwarfs it, and that only
      // the TAIL is touched.
      const rate = 16000;
      const interval = Duration(seconds: 60);
      final bound = CallAudioRecorder.maxReanchorTrimFrames(interval, rate);
      expect(bound, 192, reason: 'sanity: ~12ms at 200ppm over 60s @ 16kHz');

      final clock = _Clock();
      // A REAL 60s interval, so the trim budget below is the real ~12ms/60s
      // bound -- but an INERT timer factory, so that non-zero interval arms no
      // real `Timer.periodic`. Without the factory the only way to get a
      // non-zero budget was a non-zero interval, which started a real
      // wall-clock timer that could fire and reconcile on a slow or suspended
      // test run, racing the manual `checkpoint()` below into a double trim.
      final r = recorder(
        elapsedMs: clock.monotonic,
        reanchorInterval: interval,
        periodicTimerFactory: (_, _) => _InertTimer(),
      );
      r.onRunStarted(0, rate, 1);
      // 500ms of real audio appended while elapsed stays 0 -> the file is 500ms
      // ahead of the monotonic clock. A RAMP (sample i holds i + 1) rather than
      // a flat tone, so the surviving span is checkable value-by-value: only a
      // strictly tail trim leaves samples [0, survived) reading 1..survived;
      // any interior removal shifts every later value and shows up here.
      for (var i = 0; i < 5; i++) {
        r.onFrame(_ramp(1600, start: i * 1600 + 1)); // 100ms each; 1..8000
        await pumpEventQueue();
      }
      const wrote = 5 * 1600; // 8000 frames == 500ms
      r.checkpoint(); // reconcile at elapsed 0: overrun 8000, trim only `bound`
      final survived = wrote - bound; // 7808 frames of real audio kept

      // Advance well past the file so the finalize reconcile PADS (never trims
      // again), leaving the single checkpoint's bounded trim the only edit.
      clock.pass(2000);
      await r.finish(wasCarrier: true, callKey: _callKey);

      final wav = uploads.single.bytes;
      final content = CallAudioContent.fromJson(sent.single)!;
      // A bounded clock-drift micro-trim is NOT a ceiling cut: trimTailFrames
      // never latches cappedLogged, so this real, proven trim leaves truncated
      // false. This is the distinction `truncated` exists to draw -- a
      // ceiling-cut half is truncated, a drift-corrected one is not.
      expect(
        content.truncated,
        isFalse,
        reason: 'a clock-drift micro-trim does not mark the half truncated',
      );
      expect(content.durationMs, 2000, reason: 'padded to the elapsed end');
      expect(_wavSampleCount(wav), 2000 * rate ~/ 1000); // 32000 frames

      // Bounded AND tail-only, proven value-by-value across the WHOLE file:
      // every surviving sample still reads its original ramp value (so nothing
      // interior was removed or shifted), and everything past `survived` is the
      // finalize pad. An unbounded trim would leave the ramp region short (early
      // samples read 0); a trim into the interior would break the ramp at the
      // removal point; no trim at all would leave ramp values past `survived`.
      for (var i = 0; i < _wavSampleCount(wav); i++) {
        final expected = i < survived ? i + 1 : 0;
        if (_wavSampleAt(wav, i) != expected) {
          fail(
            'sample $i was ${_wavSampleAt(wav, i)}, expected $expected -- a '
            'bounded tail trim of exactly $bound frames leaves the interior '
            'ramp intact and pads the rest',
          );
        }
      }
    });

    test('a frame whose clock reading falls far behind the cursor is dropped, '
        'never written backwards', () async {
      // The monotonic-position guard: frames arrive in order with bounded
      // latency, but a backward clock step (or a reordered straggler) would
      // otherwise land a frame behind time already committed. Such a frame is
      // dropped rather than appended past the tail. Under the ordinary
      // non-advancing test clock this never fires (every frame shares one
      // position); it takes a deliberate backward step to exercise it.
      final clock = _Clock();
      final r = recorder(elapsedMs: clock.monotonic);
      r.onRunStarted(0, 16000, 1);
      clock.pass(5000); // elapsed 5000
      // The surviving frame: value 1000, lands at [80000, 80160); high-water 80000.
      r.onFrame(_tone(160, value: 1000));
      await pumpEventQueue();
      clock.elapsed = 4000; // a backward clock step of 1s (> the tolerance)
      // The straggler carries a DISTINCT value so its presence anywhere in the
      // file -- appended at the tail OR written backwards into the interior --
      // is detectable; its position (64000) is 1s behind the high-water, so it
      // must be dropped.
      r.onFrame(_tone(160, value: 7777));
      await pumpEventQueue();
      clock.elapsed = 5010; // end just past the surviving frame
      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      expect(
        content.durationMs,
        5010,
        reason: 'the straggler is dropped, not appended past the tail',
      );

      final wav = uploads.single.bytes;
      // Not extended by the straggler (that would be 80320 frames / 5020ms)...
      expect(_wavSampleCount(wav), 5010 * 16);
      // ...and the straggler's distinct value appears NOWHERE -- proving it was
      // neither appended at the tail nor written backwards over the interior.
      for (var i = 0; i < _wavSampleCount(wav); i++) {
        if (_wavSampleAt(wav, i) == 7777) {
          fail('the dropped straggler was written at sample $i');
        }
      }
      // The surviving frame sits untouched at its backfilled position, with the
      // pre-frame span materialised as silence.
      for (var i = 0; i < 80000; i++) {
        if (_wavSampleAt(wav, i) != 0) {
          fail('the backfill before the surviving frame was not silent at $i');
        }
      }
      for (var i = 80000; i < 80160; i++) {
        if (_wavSampleAt(wav, i) != 1000) {
          fail('the surviving frame was disturbed at sample $i');
        }
      }
    });

    test('the finalize end anchor is the audio-stop instant, not a clock read '
        'taken after the async drain and the persisted-state read', () async {
      // Finding: the finalize reconcile used to read the clock AFTER
      // `_drainPending()` and the persisted-state read. Any latency there --
      // the store read especially -- would then be padded onto the recording
      // as trailing silence, and could consume the duration cap. The end must
      // be the instant audio actually STOPPED (`onRunEnded` here), captured
      // before any await, never the moment the async finalize happened to end.
      final clock = _Clock();
      // The store's read advances the monotonic clock 3s, modelling real I/O
      // latency landing squarely between the drain and the finalize reconcile.
      final store = _ClockAdvancingReadStore(clock, byMs: 3000);
      final r = recorder(elapsedMs: clock.monotonic, uploadStateStore: store);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160)); // 10ms of real audio at elapsed 0
      clock.pass(1000); // audio runs to elapsed 1000
      r.onRunEnded(); // audio STOPS here, at elapsed 1000 -- the true end anchor
      // A real gap between the audio stop and the publish call. This is what
      // pins the onRunEnded latch SPECIFICALLY: if the end were not captured at
      // onRunEnded, the finish()-entry fallback would fix it at 1500 here, so
      // removing only the onRunEnded capture flips the assertion to 1500 (RED).
      clock.pass(500); // elapsed 1500 at finish() entry
      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      // 1000ms (where audio stopped at onRunEnded); NOT 1500ms (finish() entry,
      // were the onRunEnded latch gone) and NOT 4500ms (a late read after the
      // 3000ms store-read latency, were both captures gone).
      expect(
        content.durationMs,
        1000,
        reason:
            'the recording ends where audio stopped, not where the async '
            'finalize finished after the store read advanced the clock',
      );
      final wav = uploads.single.bytes;
      expect(_wavSampleCount(wav), 1000 * 16);
      // The whole tail past the one real frame is the finalize pad -- silence,
      // not a late-read overshoot -- proving the pad stopped at the stop instant.
      for (var i = 160; i < 1000 * 16; i++) {
        if (_wavSampleAt(wav, i) != 0) {
          fail('the finalize pad at sample $i was not silent');
        }
      }
    });

    test('the end anchor falls back to finish() entry when no onRunEnded '
        'preceded it, still ahead of the latency-inducing store read', () async {
      // `finish()` is reachable directly (call_session's publish path) with no
      // `onRunEnded` first. The anchor must then be captured at finish() ENTRY,
      // before any await -- so the same store-read latency is still excluded.
      final clock = _Clock();
      final store = _ClockAdvancingReadStore(clock, byMs: 3000);
      final r = recorder(elapsedMs: clock.monotonic, uploadStateStore: store);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160)); // 10ms of real audio at elapsed 0
      clock.pass(1000); // elapsed 1000 at the moment finish() is called
      // No onRunEnded: the fallback capture at finish() entry fixes the end.
      await r.finish(wasCarrier: true, callKey: _callKey);

      final content = CallAudioContent.fromJson(sent.single)!;
      expect(
        content.durationMs,
        1000,
        reason:
            'the finish()-entry capture fixes the end before the store read '
            'advances the clock; the 3s of latency is not padded as silence',
      );
    });
  });

  group('the duration cap lands on a whole PCM frame', () {
    test('a mono cap whose byte bound is odd is floored to a whole sample, so '
        'the WAV is never truncated mid-sample', () async {
      // 44.1kHz mono at a 15ms bound is 44100 * 1 * 2 * 15 / 1000 = 1323 bytes
      // -- an ODD number, half of a final PCM16 sample. A byte-granular cap
      // would stop `takeBytes()` at 1323 bytes, which `pcm16ToWav` writes as a
      // data chunk of 1323 bytes: 661.5 samples, a malformed WAV. The cap must
      // floor to a whole frame (1322 bytes here).
      final r = recorder(
        maxBytes: 60 * 1024 * 1024, // huge, so the 15ms duration bound binds
        maxDuration: const Duration(milliseconds: 15),
      );
      r.onRunStarted(0, 44100, 1);
      // One frame well past the cap (1000 samples = 2000 bytes > 1323): the cap
      // is what truncates it, so the cap's own alignment is what is under test.
      r.onFrame(_tone(1000));
      r.onRunEnded();
      await r.finish(wasCarrier: true, callKey: _callKey);

      final wav = uploads.single.bytes;
      final dataLen = wav.length - 44; // strip the canonical header
      expect(
        dataLen % 2,
        0,
        reason: 'PCM16 mono: the data chunk must be a whole number of samples',
      );
      expect(dataLen, 1322, reason: '1323 floored to the 2-byte frame');
      expect(_wavSampleCount(wav), 661);
    });

    test('a stereo cap whose byte bound is not a multiple of the 4-byte frame '
        'is floored to a whole stereo frame', () async {
      // 44.1kHz STEREO at a 15ms bound is 44100 * 2 * 2 * 15 / 1000 = 2646
      // bytes; the stereo frame is 4 bytes (2 channels x 2), and 2646 % 4 == 2
      // -- half a stereo frame. The cap must floor to 2644 (661 whole frames).
      final r = recorder(
        maxBytes: 60 * 1024 * 1024,
        maxDuration: const Duration(milliseconds: 15),
      );
      r.onRunStarted(0, 44100, 2); // two channels
      // 2000 interleaved int16s = 4000 bytes > 2646: the cap truncates it.
      r.onFrame(_tone(2000));
      r.onRunEnded();
      await r.finish(wasCarrier: true, callKey: _callKey);

      final wav = uploads.single.bytes;
      final dataLen = wav.length - 44;
      expect(
        dataLen % 4,
        0,
        reason:
            'PCM16 stereo: the data chunk must be a whole number of 4-byte '
            'frames, never split mid-frame by the cap',
      );
      expect(dataLen, 2644, reason: '2646 floored to the 4-byte stereo frame');
    });
  });

  group('recording-based transcription', () {
    // A recording driven end to end, so `finish` has real WAV bytes to hand to
    // the stubbed transcriber.
    void recordOneRun(CallAudioRecorder r) {
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();
    }

    test(
      'finish transcribes the recording and fills recordingSegments',
      () async {
        var called = false;
        var reqBytes = 0;
        var reqTimings = false;
        var reqRate = 0;
        String? reqL1;
        String? reqL2;
        final r = recorder(
          transcribe: (req) async {
            called = true;
            reqBytes = req.audioContent.length;
            reqTimings = req.includeWordTimings;
            reqRate = req.config.sampleRateHertz;
            reqL1 = req.config.userL1;
            reqL2 = req.config.userL2;
            return spokenWord('hola', timed: true);
          },
          userL1: 'en',
          userL2: 'es',
        );
        recordOneRun(r);
        await r.finish(wasCarrier: true, callKey: _callKey);

        // The whole recording became one utterance from the provider word list,
        // populated before finish() returned.
        expect(r.recordingSegments.map((s) => s.text).toList(), ['hola']);
        // Fed the recording's OWN bytes, asking for timings + the speaker's own
        // languages -- the same request the live chunk path makes.
        expect(called, isTrue);
        expect(reqBytes, greaterThan(0));
        expect(reqTimings, isTrue);
        // Recorded at 16kHz already, so the STT copy is not resampled.
        expect(reqRate, 16000);
        expect(reqL1, 'en');
        expect(reqL2, 'es');
        // The audio half still uploaded and sent -- transcription is additive.
        expect(uploads, hasLength(1));
        expect(sent, hasLength(1));
      },
    );

    test(
      'downsamples a 48kHz recording to 16kHz for STT (fits the request cap)',
      () async {
        var reqRate = 0;
        var reqBytes = 0;
        final r = recorder(
          transcribe: (req) async {
            reqRate = req.config.sampleRateHertz;
            reqBytes = req.audioContent.length;
            return spokenWord('hola', timed: true);
          },
          userL1: 'en',
          userL2: 'es',
        );
        // A device that captures at 48kHz (phones do). One second of tone.
        r.onRunStarted(1000, 48000, 1);
        r.onFrame(_tone(48000));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        // The STT copy is 16kHz -- a third of the samples -- while the uploaded
        // recording stays at the native 48kHz.
        expect(reqRate, 16000);
        final uploadedWav = uploads.single.bytes.length;
        expect(reqBytes, lessThan(uploadedWav));
        // ~1s at 16kHz mono PCM16 is ~32KB of samples; well under the native
        // ~96KB. Assert it is roughly a third (allow WAV-header slack).
        expect(reqBytes, lessThan(uploadedWav ~/ 2));
        expect(r.recordingSegments.map((s) => s.text).toList(), ['hola']);
      },
    );

    test(
      'a transcription failure leaves recordingSegments empty and the audio half intact',
      () async {
        final r = recorder(
          transcribe: (_) async => throw StateError('stt down'),
          userL1: 'en',
          userL2: 'es',
        );
        recordOneRun(r);
        // Non-fatal: finish() completes normally despite the STT failure.
        await r.finish(wasCarrier: true, callKey: _callKey);

        // The live transcript half stands, and the recording still uploaded/sent.
        expect(r.recordingSegments, isEmpty);
        expect(uploads, hasLength(1));
        expect(sent, hasLength(1));
      },
    );

    test('with the feature off the recording is not transcribed', () async {
      // transcribe left null == feature off.
      final r = recorder();
      recordOneRun(r);
      await r.finish(wasCarrier: true, callKey: _callKey);

      // No recording-based half; the audio was still uploaded and sent.
      expect(r.recordingSegments, isEmpty);
      expect(uploads, hasLength(1));
      expect(sent, hasLength(1));
    });

    test(
      'a device that never carried the recording never transcribes',
      () async {
        var called = false;
        final r = recorder(
          transcribe: (_) async {
            called = true;
            return spokenWord('hola', timed: true);
          },
          userL1: 'en',
          userL2: 'es',
        );
        // Recorded, but a sibling was carrying at the end: finish returns before
        // building the WAV, so transcription is never kicked off.
        recordOneRun(r);
        await r.finish(wasCarrier: false, callKey: _callKey);

        expect(called, isFalse);
        expect(r.recordingSegments, isEmpty);
        expect(uploads, isEmpty);
      },
    );

    test(
      'a long recording is transcribed in pieces and merged onto one timeline',
      () async {
        var calls = 0;
        final r = recorder(
          // 16kHz mono = 32 bytes/ms; a 48000-byte piece is 1500ms.
          sttPieceBytes: 48000,
          transcribe: (_) async => spokenWord('word${calls++}', timed: true),
          userL1: 'en',
          userL2: 'es',
        );
        // 96000 bytes at 16kHz mono = 3s -> two 1500ms pieces.
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(48000));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        // Two pieces, each its own STT request.
        expect(calls, 2);
        // Both pieces' words present, in order; the second placed 1500ms later
        // (its word timing offset by the piece's start), so a >900ms gap cuts
        // it into its own utterance -- proof the offset was applied.
        expect(r.recordingSegments.map((s) => s.text).toList(), [
          'word0',
          'word1',
        ]);
        expect(r.recordingSegments.map((s) => s.atMs).toList(), [1000, 2500]);
      },
    );

    test('a silent piece in the middle contributes no words', () async {
      var calls = 0;
      final r = recorder(
        sttPieceBytes: 48000,
        transcribe: (_) async {
          final n = calls++;
          return n == 1 ? silent : spokenWord('word$n', timed: true);
        },
        userL1: 'en',
        userL2: 'es',
      );
      // 144000 bytes = 4.5s -> three 1500ms pieces; the middle is silence.
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(72000));
      r.onRunEnded();
      await r.finish(wasCarrier: true, callKey: _callKey);

      expect(calls, 3);
      // Pieces 0 and 2 only; the silent middle is a real quiet stretch, not a
      // loss, and its absence does not shift the others (absolute placement).
      expect(r.recordingSegments.map((s) => s.text).toList(), [
        'word0',
        'word2',
      ]);
      expect(r.recordingSegments.map((s) => s.atMs).toList(), [1000, 4000]);
    });

    test(
      'a piece with a transcript but no timings abandons the whole attempt',
      () async {
        var calls = 0;
        final r = recorder(
          sttPieceBytes: 48000,
          transcribe: (_) async {
            final n = calls++;
            // The second piece has text but no word timings -> unplaceable.
            return spokenWord('word$n', timed: n == 0);
          },
          userL1: 'en',
          userL2: 'es',
        );
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(48000));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        // No partial half: the live transcript (or the server backstop) stands.
        expect(r.recordingSegments, isEmpty);
        // The audio half is unaffected.
        expect(uploads, hasLength(1));
      },
    );

    test(
      'an out-of-piece word timing is not shifted into a spurious late slot',
      () async {
        var calls = 0;
        final r = recorder(
          sttPieceBytes: 48000,
          transcribe: (_) async {
            final n = calls++;
            // Piece 0: an ordinary word. Piece 1: a word whose provider start is
            // NEGATIVE (invalid piece-local). If it were shifted by the piece
            // start (1500ms) it would land at ~1450ms and be cut into its own
            // late utterance; bounded to the piece first, it is floor-placed
            // into the running utterance instead.
            return n == 0
                ? spokenWord('a', timed: true)
                : _wordAt('b', -50, 100);
          },
          userL1: 'en',
          userL2: 'es',
        );
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(48000));
        r.onRunEnded();
        await r.finish(wasCarrier: true, callKey: _callKey);

        // One utterance -- 'b' floor-placed with 'a', not a bogus 2450ms segment.
        expect(r.recordingSegments.map((s) => s.text).toList(), ['a b']);
        expect(r.recordingSegments.single.atMs, 1000);
      },
    );
  });
}
