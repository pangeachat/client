// Dart imports:
import 'dart:async';
import 'dart:typed_data';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_recorder.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import '../sentry_capture_harness.dart';

const _callKey = '\$membership:example.com';
const _sender = '@alice:example.com';
const _device = 'DEVICEA';

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
      sent.add(content);
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
  });

  group('ownership gates the send', () {
    test('a device that never carried the recording sends nothing', () async {
      final r = recorder();
      // No onRunStarted / onFrame at all: this device never recorded.
      await r.finish(carriedOn: false, callKey: _callKey);
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
        // carriedOn is read once, at the moment the caller decided to stop
        // for good -- false here means a sibling was the last one recording.
        await r.finish(carriedOn: false, callKey: _callKey);
        expect(uploads, isEmpty);
        expect(sent, isEmpty);
      },
    );

    test(
      'a device that never opened a generation sends nothing even when carriedOn',
      () async {
        final r = recorder();
        await r.finish(carriedOn: true, callKey: _callKey);
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
        await r.finish(carriedOn: true, callKey: _callKey);
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
        await r.finish(carriedOn: true, callKey: _callKey);
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
        final finishing = r.finish(carriedOn: true, callKey: _callKey);

        // Let `finish()` run all the way up to the point it is genuinely
        // blocked on the upload gate -- draining its own queued frame and
        // calling `upload()` both now cross a microtask boundary of their
        // own, so the OLD synchronous-prefix assumption ("finish() has
        // already read `_current` by the time this line runs") no longer
        // holds without pumping first.
        await pumpEventQueue();
        expect(uploads, hasLength(1), reason: 'the first upload has started');

        // Ownership moves on WHILE the upload for the first generation is
        // still in flight -- the exact race invariant 1 names: "a device that
        // loses ownership mid-upload sends no event and uploads no blob".
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
        await r.finish(carriedOn: true, callKey: _callKey);

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
          expect(r.finish(carriedOn: true, callKey: _callKey), completes);
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
        await r.finish(carriedOn: true, callKey: _callKey);

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
        await r.finish(carriedOn: true, callKey: _callKey);

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
        await r.finish(carriedOn: true, callKey: _callKey);

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
      final finishing = r.finish(carriedOn: true, callKey: _callKey);
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

        final finishing = r.finish(carriedOn: true, callKey: _callKey);
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
        await r.finish(carriedOn: true, callKey: _callKey);

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
        await r.finish(carriedOn: true, callKey: _callKey);

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
      await r.finish(carriedOn: true, callKey: _callKey);

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

      await r.finish(carriedOn: true, callKey: _callKey);

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
      await r.finish(carriedOn: true, callKey: _callKey);

      expect(uploads, isEmpty);
      expect(sent, isEmpty);
    });

    test(
      'a persisted upload not yet confirmed sent is reused, never re-uploaded',
      () async {
        final store = InMemoryCallAudioUploadStateStore();
        final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
        await store.write(txnId, {
          'status': 'uploaded',
          'mxc_url': 'mxc://example.com/already-there',
        });

        final r = recorder(uploadStateStore: store);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(carriedOn: true, callKey: _callKey);

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
      'a successful send persists enough for a future restart to find it',
      () async {
        final store = InMemoryCallAudioUploadStateStore();
        final r = recorder(uploadStateStore: store);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(carriedOn: true, callKey: _callKey);

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
      },
    );

    test('a malformed persisted url is ignored rather than trusted', () async {
      // A cold review's finding: `Uri.tryParse` accepts an empty or
      // relative string without complaint, so a corrupted or
      // wrongly-shaped persisted record must not be trusted as a real
      // upload -- it would send an event whose url points nowhere.
      final store = InMemoryCallAudioUploadStateStore();
      final txnId = CallAudioContent.txnId(_callKey, _sender, _device);
      await store.write(txnId, {
        'status': 'uploaded',
        'mxc_url': 'not-a-valid-mxc-url',
      });

      final r = recorder(uploadStateStore: store);
      r.onRunStarted(1000, 16000, 1);
      r.onFrame(_tone(160));
      r.onRunEnded();
      await r.finish(carriedOn: true, callKey: _callKey);

      expect(
        uploads,
        hasLength(1),
        reason: 'a garbage persisted url must not be trusted',
      );
      expect(sent, hasLength(1));
      expect(sent.single['url'], 'mxc://example.com/uploaded');
    });
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
        final first = r.finish(carriedOn: true, callKey: _callKey);
        final second = r.finish(carriedOn: true, callKey: _callKey);
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
