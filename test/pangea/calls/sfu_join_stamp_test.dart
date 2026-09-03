// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/proto/livekit_models.pb.dart' as pb;
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

/// A length-delimited payload: its length as a varint, then the bytes.
List<int> _embedded(List<int> bytes) => [..._varint(bytes.length), ...bytes];

/// The BYTES livekit-server puts on the wire for one `ParticipantInfo`.
///
/// The field numbers are the contract this whole change rests on, and building
/// the message by hand is what puts them under test: `sid` is field 1,
/// `identity` is field 2, `state` is field 3, `joined_at` is field 6, `version`
/// is field 10 and `joined_at_ms` is field 17. Reading the wrong one of the two
/// time fields is not a compile error — both are int64 on the same message — so
/// nothing else here would catch it, and the same is true of `sid`/`version`,
/// the pair the store orders departed and out-of-order statements by.
///
/// Omitting a field is how proto3 sends a zero, so `joinedAtMs: null` is
/// exactly what an SFU older than livekit-server v1.8.4 puts on the wire, and
/// an omitted `state` is the JOINING default — not DISCONNECTED.
List<int> _participantBytes({
  String? sid,
  String? identity,
  int? state,
  int? joinedAtSeconds,
  int? version,
  int? joinedAtMs,
}) => [
  // field 1, length-delimited: (1 << 3) | 2
  if (sid != null) ...[0x0a, ..._embedded(sid.codeUnits)],
  // field 2, length-delimited: (2 << 3) | 2
  if (identity != null) ...[0x12, ..._embedded(identity.codeUnits)],
  // field 3, varint: (3 << 3) | 0
  if (state != null) ...[0x18, ..._varint(state)],
  // field 6, varint: (6 << 3) | 0
  if (joinedAtSeconds != null) ...[0x30, ..._varint(joinedAtSeconds)],
  // field 10, varint: (10 << 3) | 0
  if (version != null) ...[0x50, ..._varint(version)],
  // field 17, varint: (17 << 3) | 0, whose key needs two bytes
  if (joinedAtMs != null) ...[0x88, 0x01, ..._varint(joinedAtMs)],
];

/// The bytes for a join response: this device, then everyone the SFU says was
/// already in the room.
///
/// `participant` is field 2 and `other_participants` is field 3, both
/// length-delimited `ParticipantInfo`. Field 3 is the only place a join
/// response names the devices already in the room, so getting its number wrong
/// would leave them silently unread rather than fail.
List<int> _joinResponseBytes({
  String? identity,
  int? joinedAtSeconds,
  int? joinedAtMs,
  List<List<int>> others = const [],
}) => [
  // field 2, length-delimited: (2 << 3) | 2
  0x12,
  ..._embedded(
    _participantBytes(
      identity: identity,
      joinedAtSeconds: joinedAtSeconds,
      joinedAtMs: joinedAtMs,
    ),
  ),
  // field 3, length-delimited: (3 << 3) | 2
  for (final other in others) ...[0x1a, ..._embedded(other)],
];

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

  group('the stamps of the OTHER devices in the call', () {
    test('names every device the join response describes, not only ours', () {
      // Ours is in the list too. Ordering two devices needs both sides read
      // under one rule, and each side's coarse half has to come out of the same
      // frame as the fine half it refines.
      //
      // The third entry is an SFU older than livekit-server v1.8.4 seen from
      // the OTHER side: field 17 absent for that device alone, while the two
      // beside it carry one. Whether a comparison has millisecond stamps is a
      // question about a PAIR, and this is the shape of frame that makes it so.
      expect(
        sfuParticipantStampsOf(
          JoinResponse.fromBuffer(
            _joinResponseBytes(
              identity: '@ann:pangea.chat:MINE',
              joinedAtSeconds: 1787994000,
              joinedAtMs: 1787994000437,
              others: [
                _participantBytes(
                  identity: '@ann:pangea.chat:SIBLING',
                  joinedAtSeconds: 1787993999,
                  joinedAtMs: 1787993999012,
                ),
                _participantBytes(
                  identity: '@bob:pangea.chat:PEER',
                  joinedAtSeconds: 1787993998,
                ),
              ],
            ),
          ),
        ),
        [
          (
            identity: '@ann:pangea.chat:MINE',
            secondsMs: 1787994000000,
            ms: 1787994000437,
            sid: '',
            version: 0,
            hasLeft: false,
          ),
          (
            identity: '@ann:pangea.chat:SIBLING',
            secondsMs: 1787993999000,
            ms: 1787993999012,
            sid: '',
            version: 0,
            hasLeft: false,
          ),
          (
            identity: '@bob:pangea.chat:PEER',
            secondsMs: 1787993998000,
            ms: 0,
            sid: '',
            version: 0,
            hasLeft: false,
          ),
        ],
      );
    });

    test('a join response naming nobody else is just us', () {
      // The ordinary first-device-in-the-room frame. `other_participants` is a
      // repeated field, so an empty one is indistinguishable from an absent
      // one, and neither is a failure.
      expect(
        sfuParticipantStampsOf(
          JoinResponse.fromBuffer(
            _joinResponseBytes(
              identity: '@ann:pangea.chat:MINE',
              joinedAtSeconds: 1787994000,
              joinedAtMs: 1787994000437,
            ),
          ),
        ),
        [
          (
            identity: '@ann:pangea.chat:MINE',
            secondsMs: 1787994000000,
            ms: 1787994000437,
            sid: '',
            version: 0,
            hasLeft: false,
          ),
        ],
      );
    });

    test('reads a device that joined AFTER us, off a participant update', () {
      // The half without which the seam covers only the moment this device came
      // in. A device that joins later is in no join response we ever saw, and
      // `ParticipantUpdate` is where livekit_client itself learns about it.
      expect(
        sfuParticipantStampsOfUpdate([
          pb.ParticipantInfo.fromBuffer(
            _participantBytes(
              identity: '@ann:pangea.chat:LATE',
              joinedAtSeconds: 1787994060,
              joinedAtMs: 1787994060501,
            ),
          ),
          pb.ParticipantInfo.fromBuffer(
            _participantBytes(
              identity: '@bob:pangea.chat:LATER',
              joinedAtSeconds: 1787994061,
            ),
          ),
        ]),
        [
          (
            identity: '@ann:pangea.chat:LATE',
            secondsMs: 1787994060000,
            ms: 1787994060501,
            sid: '',
            version: 0,
            hasLeft: false,
          ),
          (
            identity: '@bob:pangea.chat:LATER',
            secondsMs: 1787994061000,
            ms: 0,
            sid: '',
            version: 0,
            hasLeft: false,
          ),
        ],
      );
    });

    test('carries the sid, version, and left flag the store judges by', () {
      // These three ride beside the times so the store can tell a departed or
      // out-of-order statement from the current one. Read straight off the
      // frame: `sid` field 1, `state` field 3 (DISCONNECTED is 3), `version`
      // field 7. Reading the wrong field here is not a compile error, the same
      // trap the two time fields carry, so the wire read is put under test.
      expect(
        sfuParticipantStampsOfUpdate([
          pb.ParticipantInfo.fromBuffer(
            _participantBytes(
              sid: 'PA_second',
              identity: '@ann:pangea.chat:REJOINED',
              joinedAtSeconds: 1787994060,
              version: 4,
              joinedAtMs: 1787994060501,
            ),
          ),
          pb.ParticipantInfo.fromBuffer(
            _participantBytes(
              sid: 'PA_first',
              identity: '@ann:pangea.chat:DEPARTED',
              // DISCONNECTED.
              state: 3,
              joinedAtSeconds: 1787994000,
              version: 9,
              joinedAtMs: 1787994000012,
            ),
          ),
        ]),
        [
          (
            identity: '@ann:pangea.chat:REJOINED',
            secondsMs: 1787994060000,
            ms: 1787994060501,
            sid: 'PA_second',
            version: 4,
            hasLeft: false,
          ),
          (
            identity: '@ann:pangea.chat:DEPARTED',
            secondsMs: 1787994000000,
            ms: 1787994000012,
            sid: 'PA_first',
            version: 9,
            hasLeft: true,
          ),
        ],
      );
    });

    test(
      'watches BOTH frames a device can be named in, and gives both back',
      () async {
        // A DELTA, not a count: livekit_client subscribes to that emitter itself
        // when the `SignalClient` is built, so the absolute number is not ours to
        // predict.
        //
        // Two, because there are two frames and one subscription each. This is
        // the only observation a unit test has of WHICH paths were attached —
        // neither frame can be delivered through a real `Room` here, since
        // livekit_client's own join handler builds peer connections through a
        // platform channel and its update handler waits ten seconds for a
        // `RoomConnectedEvent` no unit test can produce, once for every
        // participant the update names. Dropping either half
        // would leave devices silently unnamed rather than fail, and this count
        // is what refuses to let that pass.
        final room = Room();
        final before = joinStampWatchCount(room);

        final cancel = watchSfuParticipantStamps(room, (_) {});
        expect(
          joinStampWatchCount(room) - before,
          2,
          reason: 'the join response and the later updates are separate frames',
        );

        // ONE canceller for two subscriptions, so a caller that gives the watch
        // back gives all of it back.
        await cancel();
        expect(
          joinStampWatchCount(room),
          before,
          reason: 'cancelling must release both, not the first',
        );
      },
    );
  });
}
