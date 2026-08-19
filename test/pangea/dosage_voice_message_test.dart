import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/dosage/dosage_voice_message.dart';

/// The [DosageVoiceMessage] model — the client-reported half of speaking.
///
/// Two things are load-bearing and pinned here: the wire is EXACTLY the four
/// keys the server's `extra="forbid"` ingest accepts (a fifth would 422 the whole
/// batch), and [DosageVoiceMessage.isValid] mirrors the server's own bounds so a
/// value that would 422 is dropped on the client first rather than sent.
void main() {
  DosageVoiceMessage message({
    String msgId = '\$event:example.org',
    String roomId = '!room:example.org',
    int durationMs = 4200,
    DateTime? ts,
  }) => DosageVoiceMessage(
    msgId: msgId,
    roomId: roomId,
    durationMs: durationMs,
    ts: ts ?? DateTime.utc(2026, 8, 19, 12, 30),
  );

  group('toJson wire shape', () {
    test('carries EXACTLY the four contract keys, no sender', () {
      final json = message().toJson();
      expect(
        json.keys.toSet(),
        {'msg_id', 'room_id', 'duration_ms', 'ts'},
        reason: 'the ingest is extra="forbid"; a fifth key 422s the batch',
      );
      expect(json.containsKey('sender'), isFalse);
    });

    test('values pass through verbatim; ts is UTC ISO-8601', () {
      final json = message(
        msgId: '\$abc:server',
        roomId: '!dm:server',
        durationMs: 12345,
      ).toJson();
      expect(json['msg_id'], '\$abc:server');
      expect(json['room_id'], '!dm:server');
      expect(json['duration_ms'], 12345);
      expect(json['ts'], '2026-08-19T12:30:00.000Z');
    });

    test('a local-zone ts is serialised as UTC (tz-aware Z)', () {
      // Server field is AwareDatetime; a naive/local string would be rejected.
      final local = DateTime(2026, 8, 19, 12, 30);
      final iso = message(ts: local).toJson()['ts'] as String;
      expect(iso.endsWith('Z'), isTrue);
      expect(DateTime.parse(iso), local.toUtc());
    });
  });

  group('isValid mirrors the server bounds', () {
    test('a well-formed row is valid', () {
      expect(message().isValid, isTrue);
    });

    test(
      'duration 0 and the exact 4h ceiling are valid (server ge=0, le=cap)',
      () {
        expect(message(durationMs: 0).isValid, isTrue);
        expect(
          message(durationMs: DosageVoiceMessage.maxDurationMs).isValid,
          isTrue,
        );
      },
    );

    test(
      'a negative or over-ceiling duration is invalid (dropped, not clamped)',
      () {
        expect(message(durationMs: -1).isValid, isFalse);
        expect(
          message(durationMs: DosageVoiceMessage.maxDurationMs + 1).isValid,
          isFalse,
        );
      },
    );

    test('a blank or whitespace msg id is invalid', () {
      expect(message(msgId: '').isValid, isFalse);
      expect(message(msgId: '   ').isValid, isFalse);
    });

    test('an empty room id is invalid', () {
      expect(message(roomId: '').isValid, isFalse);
    });

    test('the ceiling equals the server MAX_PLAYBACK_MS (4h)', () {
      expect(DosageVoiceMessage.maxDurationMs, 4 * 60 * 60 * 1000);
    });
  });
}
