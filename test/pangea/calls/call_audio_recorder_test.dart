// Dart imports:
import 'dart:async';
import 'dart:typed_data';

// Package imports:
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_test/flutter_test.dart';

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

      await r.finish(carriedOn: true, callKey: _callKey);

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
          // Matches the fresh recorder's own first (and only) generation
          // below -- ids start at 0 -- which is exactly the fact the reuse
          // check requires. See the "DIFFERENT generation" test for what
          // happens when it does not match.
          'generation_id': 0,
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
          // No generation this recorder ever creates is assigned a
          // negative id (they start at 0 and only increase), so this can
          // never legitimately match -- simulating exactly the earlier,
          // superseded generation's own leftover record.
          'generation_id': -1,
        });

        final r = recorder(uploadStateStore: store);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(carriedOn: true, callKey: _callKey);

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
        expect(persisted['generation_id'], 0);
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
        'generation_id': 0,
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
        await store.write(txnId, {
          'status': 'uploaded',
          'mxc_url': 'mxc://example.com',
          'generation_id': 0,
        });

        final r = recorder(uploadStateStore: store);
        r.onRunStarted(1000, 16000, 1);
        r.onFrame(_tone(160));
        r.onRunEnded();
        await r.finish(carriedOn: true, callKey: _callKey);

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
        await r.finish(carriedOn: true, callKey: _callKey);

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
