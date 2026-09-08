// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

const _callKey = '\$membership:example.com';
const _alice = '@alice:example.com';

CallAudioContent _content({
  String callKey = _callKey,
  String? deviceId = 'DEVICEA',
  String url = 'mxc://example.com/abc123',
  String mimetype = 'audio/wav',
  int size = 4096,
  int durationMs = 30000,
  int sampleRate = 16000,
  int channels = 1,
  String codec = kCallAudioCodec,
  ClockAnchor? clockAnchor,
  int? recordingStartedOffsetFromDeviceJoinMs,
  bool truncated = false,
}) => CallAudioContent(
  callKey: callKey,
  deviceId: deviceId,
  url: url,
  mimetype: mimetype,
  size: size,
  durationMs: durationMs,
  sampleRate: sampleRate,
  channels: channels,
  codec: codec,
  clockAnchor: clockAnchor,
  recordingStartedOffsetFromDeviceJoinMs:
      recordingStartedOffsetFromDeviceJoinMs,
  truncated: truncated,
);

void main() {
  group('CallAudioContent json', () {
    test('round-trips everything a reader depends on', () {
      final parsed = CallAudioContent.fromJson(
        _content(
          clockAnchor: const ClockAnchor(
            sfuMs: 1787994000000,
            deviceMs: 1787994000123,
          ),
          recordingStartedOffsetFromDeviceJoinMs: 842,
        ).toJson(),
      )!;

      expect(parsed.callKey, _callKey);
      expect(parsed.deviceId, 'DEVICEA');
      expect(parsed.url, 'mxc://example.com/abc123');
      expect(parsed.mimetype, 'audio/wav');
      expect(parsed.size, 4096);
      expect(parsed.durationMs, 30000);
      expect(parsed.sampleRate, 16000);
      expect(parsed.channels, 1);
      expect(parsed.codec, kCallAudioCodec);
      expect(
        parsed.clockAnchor,
        const ClockAnchor(sfuMs: 1787994000000, deviceMs: 1787994000123),
      );
      expect(parsed.recordingStartedOffsetFromDeviceJoinMs, 842);
    });

    test('carries the relation that makes it findable', () {
      final json = _content().toJson();
      expect(json['m.relates_to'], {
        'rel_type': 'pangea.call_audio',
        'event_id': _callKey,
      });
    });

    test('leaves out device_id, clock anchor and offset when absent', () {
      final json = _content(
        deviceId: null,
        clockAnchor: null,
        recordingStartedOffsetFromDeviceJoinMs: null,
      ).toJson();
      expect(json.containsKey('device_id'), isFalse);
      expect(json.containsKey('sfu_joined_at_ms'), isFalse);
      expect(json.containsKey('device_joined_at_ms'), isFalse);
      expect(
        json.containsKey('recording_started_offset_from_device_join_ms'),
        isFalse,
      );

      final parsed = CallAudioContent.fromJson(json)!;
      expect(parsed.deviceId, isNull);
      expect(parsed.clockAnchor, isNull);
      expect(parsed.recordingStartedOffsetFromDeviceJoinMs, isNull);
    });

    test(
      'a malformed device id is absent, not a refusal of the whole half',
      () {
        final json = _content().toJson();
        json['device_id'] = 12345; // somebody else's word: wrong type
        final parsed = CallAudioContent.fromJson(json)!;
        expect(parsed.deviceId, isNull);
      },
    );

    test('refuses content with no call key', () {
      final json = _content().toJson();
      json.remove('call_key');
      expect(CallAudioContent.fromJson(json), isNull);
    });

    test('refuses an empty call key', () {
      final json = _content().toJson()..['call_key'] = '';
      expect(CallAudioContent.fromJson(json), isNull);
    });

    test('refuses content with no url', () {
      final json = _content().toJson();
      json.remove('url');
      expect(CallAudioContent.fromJson(json), isNull);
    });

    test('refuses a non-positive sample rate or channel count', () {
      final zeroRate = _content().toJson()..['sample_rate'] = 0;
      expect(CallAudioContent.fromJson(zeroRate), isNull);

      final negativeChannels = _content().toJson()..['channels'] = -1;
      expect(CallAudioContent.fromJson(negativeChannels), isNull);
    });

    test('refuses a malformed size or duration rather than guessing', () {
      final badSize = _content().toJson()..['size'] = 'a lot';
      expect(CallAudioContent.fromJson(badSize), isNull);

      final negativeDuration = _content().toJson()..['duration_ms'] = -1;
      expect(CallAudioContent.fromJson(negativeDuration), isNull);
    });

    test('an anchor needs BOTH clock fields or neither', () {
      final halfAnchor = _content().toJson();
      halfAnchor['sfu_joined_at_ms'] = 1787994000000;
      // device_joined_at_ms deliberately left off.
      final parsed = CallAudioContent.fromJson(halfAnchor)!;
      expect(parsed.clockAnchor, isNull);
    });
  });

  group('CallAudioContent.fileStartSfuMs', () {
    test('is the SFU join stamp plus the recording-start offset', () {
      final content = _content(
        clockAnchor: const ClockAnchor(sfuMs: 1000, deviceMs: 1050),
        recordingStartedOffsetFromDeviceJoinMs: 250,
      );
      expect(content.fileStartSfuMs, 1250);
    });

    test('is null when either half of the alignment is missing', () {
      expect(
        _content(
          clockAnchor: null,
          recordingStartedOffsetFromDeviceJoinMs: 250,
        ).fileStartSfuMs,
        isNull,
      );
      expect(
        _content(
          clockAnchor: const ClockAnchor(sfuMs: 1000, deviceMs: 1050),
          recordingStartedOffsetFromDeviceJoinMs: null,
        ).fileStartSfuMs,
        isNull,
      );
    });
  });

  group('CallAudioContent.txnId', () {
    test('is deterministic in (call key, sender, device)', () {
      final a = CallAudioContent.txnId(_callKey, _alice, 'DEVICEA');
      final b = CallAudioContent.txnId(_callKey, _alice, 'DEVICEA');
      expect(a, b);
    });

    test('differs by device, so two devices of one account are two halves', () {
      final a = CallAudioContent.txnId(_callKey, _alice, 'DEVICEA');
      final b = CallAudioContent.txnId(_callKey, _alice, 'DEVICEB');
      expect(a, isNot(b));
    });

    test('a device this reader cannot use scopes like no device at all', () {
      final unusable = CallAudioContent.txnId(_callKey, _alice, '');
      final absent = CallAudioContent.txnId(_callKey, _alice, null);
      expect(unusable, absent);
    });
    // Note: there is deliberately NO "truncated does not change the txnId"
    // test here. truncated is not one of txnId's parameters, so any such test
    // could only compare identical calls -- tautological, false coverage. The
    // key's independence from truncation is a structural fact of the signature
    // (see CallAudioContent.txnId) and is documented at the field itself; the
    // "deterministic in (call key, sender, device)" test above pins the inputs
    // that DO define it.
  });

  group('CallAudioContent.truncated', () {
    test('round-trips true', () {
      final json = _content(truncated: true).toJson();
      expect(json['truncated'], true);
      final parsed = CallAudioContent.fromJson(json)!;
      expect(parsed.truncated, isTrue);
    });

    test(
      'is omitted from the wire when false, and absence parses as false',
      () {
        final json = _content(truncated: false).toJson();
        expect(json.containsKey('truncated'), isFalse);
        final parsed = CallAudioContent.fromJson(json)!;
        expect(parsed.truncated, isFalse);
      },
    );

    test('a non-true value parses as false rather than refusing the half', () {
      final json = _content().toJson();
      json['truncated'] = 'yes';
      final parsed = CallAudioContent.fromJson(json)!;
      expect(parsed.truncated, isFalse);

      json['truncated'] = 0;
      final parsedAgain = CallAudioContent.fromJson(json)!;
      expect(parsedAgain.truncated, isFalse);

      // An explicit `false` on the wire (never emitted by THIS writer, since
      // toJson omits the key rather than writing it -- but a foreign or
      // future client is free to write it explicitly) must parse the same
      // way absence does.
      json['truncated'] = false;
      final parsedExplicitFalse = CallAudioContent.fromJson(json)!;
      expect(parsedExplicitFalse.truncated, isFalse);
    });
  });
}
