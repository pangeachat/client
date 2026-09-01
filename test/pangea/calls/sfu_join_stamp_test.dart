// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/src/proto/livekit_rtc.pb.dart';

import 'package:fluffychat/routes/chat/calls/sfu_join_stamp.dart';

/// A protobuf varint, the encoding every integer field on this wire uses.
List<int> _varint(int value) {
  final out = <int>[];
  var rest = value;
  while (rest >= 0x80) {
    out.add((rest & 0x7f) | 0x80);
    rest >>= 7;
  }
  return out..add(rest);
}

/// The BYTES livekit-server puts on the wire for a join response, rather than a
/// message built through the generated setters.
///
/// The field numbers are the contract this whole change rests on, and building
/// the message by hand is what puts them under test: `joined_at` is field 6 and
/// `joined_at_ms` is field 17 of `ParticipantInfo`, which is field 2 of
/// `JoinResponse`. Reading the wrong one is not a compile error — both are
/// int64 on the same message — so nothing else here would catch it.
///
/// Omitting a field is how proto3 sends a zero, so `joinedAtMs: null` is
/// exactly what an SFU older than livekit-server v1.8.4 puts on the wire.
List<int> _joinResponseBytes({int? joinedAtSeconds, int? joinedAtMs}) {
  final participant = <int>[
    // field 6, varint: (6 << 3) | 0
    if (joinedAtSeconds != null) ...[0x30, ..._varint(joinedAtSeconds)],
    // field 17, varint: (17 << 3) | 0, whose key needs two bytes
    if (joinedAtMs != null) ...[0x88, 0x01, ..._varint(joinedAtMs)],
  ];
  // field 2, length-delimited: (2 << 3) | 2
  return [0x12, ..._varint(participant.length), ...participant];
}

({int secondsMs, int ms}) _stampsFrom(List<int> joinResponse) =>
    sfuJoinStampsOf(JoinResponse.fromBuffer(joinResponse));

void main() {
  group('the SFU join stamp read past the livekit_client API', () {
    test('reads BOTH stamps, and does not confuse them', () {
      // The whole point of the deep import is the 437ms. `secondsMs` has to be
      // the coarse field scaled the way `Participant.joinedAt` scales it, so
      // the caller can check one against the other without a second source —
      // reading field 6 where field 17 was meant would compile and produce a
      // number that looks perfectly reasonable.
      expect(
        _stampsFrom(
          _joinResponseBytes(
            joinedAtSeconds: 1787994000,
            joinedAtMs: 1787994000437,
          ),
        ),
        (secondsMs: 1787994000000, ms: 1787994000437),
      );
    });

    test('the fine stamp is zero when the server sent no such field', () {
      // An SFU older than livekit-server v1.8.4. Proto3 leaves defaults off the
      // wire, so absent arrives as zero, and this passes that on rather than
      // judging it — what to do about it is decided in one place, in
      // `CallMedia.anchorClocksTo`. The coarse stamp is unaffected, which is
      // what lets an older server still get the paired device reading.
      expect(_stampsFrom(_joinResponseBytes(joinedAtSeconds: 1787994000)), (
        secondsMs: 1787994000000,
        ms: 0,
      ));
    });

    test('a frame with no participant at all is zeros, not a throw', () {
      // This runs inside `Room.connect`, on a frame nothing has validated. An
      // exception here would come back out of the connect and fail a call whose
      // audio was about to work perfectly well.
      expect(_stampsFrom(const []), (secondsMs: 0, ms: 0));
    });
  });
}
