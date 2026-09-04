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

  CallAudioRecorder recorder({
    ClockAnchor? Function()? clockAnchor,
    int maxBytes = 60 * 1024 * 1024,
    Duration maxDuration = const Duration(minutes: 30),
    Duration retryDelay = Duration.zero,
  }) => CallAudioRecorder(
    senderId: _sender,
    deviceId: _device,
    clockAnchor: clockAnchor,
    maxBytes: maxBytes,
    maxDuration: maxDuration,
    retryDelay: retryDelay,
    upload: (bytes, {required filename, required contentType}) async {
      uploads.add((bytes: bytes, filename: filename, contentType: contentType));
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

        // Ownership moves on WHILE the upload for the first generation is
        // still in flight -- the exact race invariant 1 names: "a device that
        // loses ownership mid-upload sends no event and uploads no blob".
        r.onRunStarted(5000, 16000, 1);
        r.onFrame(_tone(160));

        // Let the FIRST upload finally answer. If the gate were not honoured
        // this would let the stale send through.
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
}
