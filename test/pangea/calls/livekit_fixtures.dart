// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/proto/livekit_models.pb.dart' as pb;

/// The test-side twin of `lib/routes/chat/calls/sfu_join_stamp.dart`: the one
/// place the call tests reach past livekit_client's public API, kept here so
/// the deep import is in a single file on this side too.
///
/// It exists because `LocalParticipant`'s constructor is private and the only
/// way in, `createFromInfo`, takes a proto message the package does not export.
/// Without it a test cannot put a participant in a room, and the branch of
/// `CallMedia._publishingAs` that HAS one is unreachable — which is exactly
/// where the removed join-time fallback used to sit, so leaving it unreachable
/// would leave that regression unpinned.

/// A real [LocalParticipant] whose `joinedAt` is [joinedAtSeconds].
///
/// Built through livekit_client's own factory rather than faked, so the
/// `joinedAt` a caller reads off it is derived the way the real one is: proto
/// field 6, in whole seconds, multiplied by a thousand.
Future<LocalParticipant> participantJoinedAt(int joinedAtSeconds) =>
    LocalParticipant.createFromInfo(
      room: Room(),
      // From the WIRE rather than the generated setters, which would need
      // `fixnum` for the int64 and it is not a direct dependency here. The
      // field numbers are livekit's: sid 1, identity 2, joined_at 6.
      info: pb.ParticipantInfo.fromBuffer([
        0x0a,
        ..._lengthDelimited('sid'),
        0x12,
        ..._lengthDelimited('me'),
        0x30,
        ..._varint(joinedAtSeconds),
      ]),
    );

List<int> _lengthDelimited(String value) => [value.length, ...value.codeUnits];

List<int> _varint(int value) {
  final out = <int>[];
  var rest = value;
  while (rest >= 0x80) {
    out.add((rest & 0x7f) | 0x80);
    rest >>= 7;
  }
  return out..add(rest);
}

/// A room that reports [participant] as the local one, which a real [Room]
/// only does after a connection this suite cannot make.
class RoomWithParticipant extends Room {
  RoomWithParticipant(this.participant);

  final LocalParticipant participant;

  @override
  LocalParticipant? get localParticipant => participant;
}
