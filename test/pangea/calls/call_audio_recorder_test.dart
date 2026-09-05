// Dart imports:
import 'dart:async';
import 'dart:typed_data';

// Package imports:
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Logs;

// Project imports:
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_recorder.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import '../sentry_capture_harness.dart';

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

/// [n] frames of [samplesPerFrame] mono 16-bit samples, all equal to [value]
/// -- a fixed tone (or, at value 0, digital silence) cheap to assert on.
Int16List _tone(int samplesPerFrame, {int value = 1000}) =>
    Int16List.fromList(List.filled(samplesPerFrame, value));

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
  }) => CallAudioRecorder(
    senderId: _sender,
    deviceId: _device,
    clockAnchor: clockAnchor,
    maxBytes: maxBytes,
    maxDuration: maxDuration,
    retryDelay: retryDelay,
    uploadStateStore: uploadStateStore,
    maxPendingFrames: maxPendingFrames,
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
}
