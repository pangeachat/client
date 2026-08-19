import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'package:fluffychat/routes/chat/calls/call_roster.dart';

/// A roster whose two connection-dependent reads are supplied by the test.
///
/// Everything else — who counts as a peer, who counts as a sibling device, and
/// the freeze while the connection is down — is the real implementation.
class TestRoster extends CallRoster {
  TestRoster({required super.room, required super.myUserId});

  Set<String> identities = {};
  bool connected = true;

  @override
  Iterable<String> get remoteIdentities => identities;

  @override
  bool get roomConnected => connected;
}

void main() {
  const me = '@learner:pangea.localhost';
  const peer = '@calltester:pangea.localhost';

  late lk.Room room;
  late TestRoster roster;
  late int notifications;

  setUp(() {
    room = lk.Room();
    roster = TestRoster(room: room, myUserId: me);
    notifications = 0;
    roster.addListener(() => notifications++);
  });

  tearDown(() => roster.dispose());

  group('reading who is in the call', () {
    test('sees a peer who was already here before this device joined', () {
      // The whole reason presence is read as state. Someone already in the room
      // when this device connects raises no join event — and that is exactly
      // the situation of every person ANSWERING a call. Deriving presence from
      // events instead of the list would make answering do nothing at all,
      // which is the bug this pins.
      roster.identities = {'$peer:THEIRPHONE'};
      roster.recompute();

      expect(roster.hasPeer, isTrue);
      expect(roster.participants, {
        const CallParticipant(userId: peer, deviceId: 'THEIRPHONE'),
      });
    });

    test('an empty call has no peer', () {
      roster.recompute();
      expect(roster.hasPeer, isFalse);
    });

    test('this account alone on another device is not a peer', () {
      // Two of your own devices in a call is not a conversation. Counting it as
      // one would tell the caller their call had been answered by themselves.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.recompute();

      expect(roster.hasPeer, isFalse);
      expect(roster.siblingDeviceIds, ['MYOTHERPHONE']);
    });

    test('separates a peer from this account own other devices', () {
      roster.identities = {'$me:MYOTHERPHONE', '$peer:THEIRPHONE'};
      roster.recompute();

      expect(roster.hasPeer, isTrue);
      expect(roster.siblingDeviceIds, ['MYOTHERPHONE']);
    });

    test('a peer leaving is seen', () {
      roster.identities = {'$peer:THEIRPHONE'};
      roster.recompute();
      expect(roster.hasPeer, isTrue);

      roster.identities = {};
      roster.recompute();
      expect(roster.hasPeer, isFalse);
    });
  });

  group('naming participants', () {
    test('splits a user id from its device', () {
      final p = CallParticipant.parse('@learner:pangea.localhost:ABCDEF');
      expect(p.userId, '@learner:pangea.localhost');
      expect(p.deviceId, 'ABCDEF');
    });

    test('a bare user id carries no device', () {
      // The colon inside a Matrix user id must not be mistaken for a device
      // separator, or every participant would be read as a different user.
      final p = CallParticipant.parse('@learner:pangea.localhost');
      expect(p.userId, '@learner:pangea.localhost');
      expect(p.deviceId, isNull);
    });

    test('this account own id is matched exactly, port and all', () {
      // A homeserver may carry a port, so `@u:host:8448` is both a plausible
      // bare user id and a plausible user-plus-device. Knowing our own id is
      // what settles it — guessing wrong would read our own second device as
      // another person and tell a caller their call had been answered.
      const mine = '@learner:localhost:8448';
      expect(
        CallParticipant.parse(mine, myUserId: mine),
        const CallParticipant(userId: mine),
      );
      expect(
        CallParticipant.parse('$mine:PHONE', myUserId: mine),
        const CallParticipant(userId: mine, deviceId: 'PHONE'),
      );
    });

    test('our own device is never counted as a peer', () {
      const mine = '@learner:localhost:8448';
      final ported = TestRoster(room: room, myUserId: mine)
        ..identities = {'$mine:PHONE'}
        ..recompute();
      addTearDown(ported.dispose);

      expect(ported.hasPeer, isFalse);
      expect(ported.siblingDeviceIds, ['PHONE']);
    });

    test('a homeserver with a port still parses', () {
      final p = CallParticipant.parse('@learner:localhost:8008:DEVICE');
      expect(p.userId, '@learner:localhost:8008');
      expect(p.deviceId, 'DEVICE');
    });

    test('something that is not a user id is left whole', () {
      // Never split something unrecognisable into a user we might match on.
      final p = CallParticipant.parse('recorder-bot');
      expect(p.userId, 'recorder-bot');
      expect(p.deviceId, isNull);
    });

    test('an unparseable identity is never mistaken for this account', () {
      roster.identities = {'recorder-bot'};
      roster.recompute();
      // Counted as a peer, not silently ignored: something IS in the call.
      expect(roster.hasPeer, isTrue);
      expect(roster.siblingDeviceIds, isEmpty);
    });
  });

  group('while the connection is down', () {
    setUp(() {
      roster.identities = {'$peer:THEIRPHONE'};
      roster.recompute();
    });

    test('holds the last picture instead of reporting everyone gone', () {
      // A full reconnect empties the participant list and reports every
      // participant as disconnected before silently refilling it. Believing
      // that would read as the other person hanging up, and would end a call
      // over a momentary network blip.
      roster.connected = false;
      roster.identities = {};
      roster.recompute();

      expect(
        roster.hasPeer,
        isTrue,
        reason: 'a blip is not the other person leaving',
      );
      expect(roster.isConnected, isFalse);
    });

    test('picks the truth back up once reconnected', () {
      roster.connected = false;
      roster.identities = {};
      roster.recompute();

      // The peer really did leave while we were away.
      roster.connected = true;
      roster.recompute();
      expect(roster.hasPeer, isFalse);
    });

    test('a peer who was there all along is still there after a reconnect', () {
      roster.connected = false;
      roster.identities = {};
      roster.recompute();

      // Refilled silently on rejoin, with no join event for anyone — so this
      // has to come from re-reading the list.
      roster.connected = true;
      roster.identities = {'$peer:THEIRPHONE'};
      roster.recompute();
      expect(roster.hasPeer, isTrue);
    });
  });

  group('telling listeners', () {
    test('notifies when the participants change', () {
      final before = notifications;
      roster.identities = {'$peer:THEIRPHONE'};
      roster.recompute();
      expect(notifications, greaterThan(before));
    });

    test('stays quiet when nothing changed', () {
      roster.identities = {'$peer:THEIRPHONE'};
      roster.recompute();
      final settled = notifications;
      roster.recompute();
      expect(
        notifications,
        settled,
        reason: 'a redundant notification re-runs the whole call lifecycle',
      );
    });

    test(
      'notifies when the connection drops, so listeners can stop deciding',
      () {
        final before = notifications;
        roster.connected = false;
        roster.recompute();
        expect(notifications, greaterThan(before));
      },
    );

    test('stops listening to the room once disposed', () {
      roster.dispose();
      final settled = notifications;
      // The room outlives the roster during teardown; a roster still attached
      // to it would keep deciding things about a call that has ended.
      room.notifyListeners();
      expect(notifications, settled);
      // Re-disposal in tearDown must stay safe.
      roster = TestRoster(room: room, myUserId: me);
    });
  });
}
