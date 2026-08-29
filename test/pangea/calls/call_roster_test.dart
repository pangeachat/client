import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/capture_election.dart';

/// A roster whose SFU read and connection state are supplied by the test.
///
/// Everything else — who counts as a peer, who counts as a sibling device, what
/// makes a join time believable, and the freeze while the connection is down —
/// is the real implementation.
class TestRoster extends CallRoster {
  TestRoster({required super.room, required super.myUserId});

  Set<String> identities = {};
  bool connected = true;

  /// Whether the connection is still trying, as opposed to having given up.
  bool recovering = true;

  /// identity -> (publications, muted). Unlisted identities have none.
  Map<String, (int, int)> audio = {};

  /// identity -> the stamp the SFU put on their join.
  Map<String, DateTime> joins = {};

  /// Identities the SFU has not described yet. The SDK's `joinedAt` is
  /// NON-NULLABLE, so for these it answers with a fresh read of this device's
  /// own clock — which is not a join time at all, and is a different value
  /// every time it is asked.
  Set<String> undescribed = {};

  /// identity -> published attributes.
  Map<String, Map<String, String>> attributes = {};

  /// This device's own join stamp. Null when the SFU has given us no local
  /// participant at all.
  DateTime? myJoin = DateTime.utc(2026, 8, 29, 12);

  /// Whether the SFU has described THIS device.
  bool myDescribed = true;

  /// Strictly increasing, so a test can never pass by the local clock happening
  /// to read the same twice inside one microsecond.
  var _localClock = DateTime.utc(2030);
  DateTime get _freshLocalRead =>
      _localClock = _localClock.add(const Duration(seconds: 1));

  /// What was written to the wire, in order, and how each write answered.
  final List<Map<String, String>> published = [];

  /// Held open by a test to keep a write in flight.
  Completer<void>? holdPublish;

  /// Set to make the write fail the way a token without the metadata grant
  /// does: setAttributes throws rather than returning false.
  Object? publishError;

  @override
  RosterRead get read => RosterRead(
    remotes: [
      for (final id in identities)
        RosterMember(
          identity: id,
          described: !undescribed.contains(id),
          joinedAt: undescribed.contains(id)
              ? _freshLocalRead
              : (joins[id] ?? _defaultJoin),
          audioPublications: (audio[id] ?? (0, 0)).$1,
          mutedAudioPublications: (audio[id] ?? (0, 0)).$2,
          attributes: attributes[id] ?? const {},
        ),
    ],
    me: myJoin == null
        ? null
        : RosterMember(
            identity: myUserId,
            described: myDescribed,
            joinedAt: myDescribed ? myJoin! : _freshLocalRead,
          ),
  );

  @override
  Future<bool> publishAttributes(Map<String, String> attributes) async {
    published.add(attributes);
    if (holdPublish != null) await holdPublish!.future;
    if (publishError != null) throw publishError!;
    return true;
  }

  @override
  bool get roomConnected => connected;

  @override
  bool get roomRecovering => !connected && recovering;
}

/// A believable join stamp for the tests that are not about join times.
final _defaultJoin = DateTime.utc(2026, 8, 29, 12);

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

    test('holds the last picture while the connection is coming back', () {
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

    test('lets it go once the connection has gone for good', () {
      // Holding it then means the call is never seen to end, and the microphone
      // stays open in a conversation that finished when the connection did.
      roster.connected = false;
      roster.recovering = false;
      roster.recompute();

      expect(roster.hasPeer, isFalse);
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
  group('whether the peer can be heard', () {
    test('shows muted only when every peer publication is muted', () {
      roster.identities = {'$peer:PHONE', '$peer:LAPTOP'};
      roster.audio = {'$peer:PHONE': (1, 1), '$peer:LAPTOP': (1, 0)};
      roster.recompute();
      expect(roster.peerMuted, isFalse, reason: 'one audible device suffices');

      roster.audio = {'$peer:PHONE': (1, 1), '$peer:LAPTOP': (1, 1)};
      roster.recompute();
      expect(roster.peerMuted, isTrue);

      roster.audio = {'$peer:PHONE': (1, 0), '$peer:LAPTOP': (1, 1)};
      roster.recompute();
      expect(roster.peerMuted, isFalse, reason: 'unmute clears the badge');
    });

    test('no publications is no signal, not muted', () {
      roster.identities = {'$peer:PHONE'};
      roster.audio = {'$peer:PHONE': (0, 0)};
      roster.recompute();
      expect(roster.peerMuted, isFalse);
    });

    test("this account's own muted sibling never paints the peer muted", () {
      roster.identities = {'$me:OTHERPHONE', '$peer:PHONE'};
      roster.audio = {'$me:OTHERPHONE': (1, 1), '$peer:PHONE': (1, 0)};
      roster.recompute();
      expect(roster.peerMuted, isFalse);
    });

    test('a mute change alone notifies listeners', () {
      roster.identities = {'$peer:PHONE'};
      roster.audio = {'$peer:PHONE': (1, 0)};
      roster.recompute();
      final before = notifications;

      // Same participants, only the mute flag moved.
      roster.audio = {'$peer:PHONE': (1, 1)};
      roster.recompute();
      expect(notifications, greaterThan(before), reason: 'the badge repaints');
      expect(roster.peerMuted, isTrue);
    });
  });

  group('when the SFU says a device joined', () {
    final joined = DateTime.utc(2026, 8, 29, 12, 0, 30);

    test('a stamped join time is carried through', () {
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.joins = {'$me:MYOTHERPHONE': joined};
      roster.recompute();

      expect(roster.siblingJoinTime('MYOTHERPHONE'), joined);
    });

    test('a device the SFU has not described has no join time', () {
      // The SDK's joinedAt is NON-NULLABLE: with no server info it answers with
      // a fresh read of THIS device's clock. Believing that would place a
      // sibling's join wherever we happened to be looking from -- and since the
      // reading moves every time it is asked, it would also make every read of
      // the roster look like a change.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.undescribed = {'$me:MYOTHERPHONE'};
      roster.recompute();

      expect(roster.siblingJoinTime('MYOTHERPHONE'), isNull);

      final settled = notifications;
      roster.recompute();
      roster.recompute();
      expect(
        notifications,
        settled,
        reason: 'and a moving clock read does not become a roster change',
      );
    });

    test('a join time nobody stamped is not believed', () {
      // Zero is the protocol default, which reads as 1970. An offset measured
      // against 1970 is this device's ENTIRE clock rather than its disagreement
      // with anything, which is why the transcript writer already refuses it.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.joins = {
        '$me:MYOTHERPHONE': DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      };
      roster.recompute();

      expect(roster.siblingJoinTime('MYOTHERPHONE'), isNull);
    });

    test('this device own join time follows the same rule', () {
      roster.myJoin = joined;
      roster.recompute();
      expect(roster.myJoinTime, joined);

      roster.myDescribed = false;
      roster.recompute();
      expect(roster.myJoinTime, isNull);
    });

    test('a join time arriving alone notifies listeners', () {
      // The participant SET is unchanged -- the same device, in the same call.
      // Only the SFU's description of it moved, and the election reads that.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.undescribed = {'$me:MYOTHERPHONE'};
      roster.recompute();
      final before = notifications;

      roster.undescribed = {};
      roster.joins = {'$me:MYOTHERPHONE': joined};
      roster.recompute();

      expect(notifications, greaterThan(before));
      expect(roster.siblingJoinTime('MYOTHERPHONE'), joined);
    });
  });

  group('what a device says about whether it can record', () {
    test('a device that has published nothing reads as able', () {
      // Silence has to read as ABLE. An older build publishes no attribute at
      // all, and reading that as "cannot" would have every device out-rank
      // every sibling it had not yet heard from.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.recompute();

      expect(roster.siblingCanCapture('MYOTHERPHONE'), isTrue);
    });

    test('a device nobody can see reads as able too', () {
      roster.recompute();
      expect(roster.siblingCanCapture('NEVERHEARDOFIT'), isTrue);
    });

    test('a device that said it cannot is taken at its word', () {
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.attributes = {
        '$me:MYOTHERPHONE': {CallRoster.canCaptureAttribute: 'no'},
      };
      roster.recompute();

      expect(roster.siblingCanCapture('MYOTHERPHONE'), isFalse);
    });

    test('a capability change alone notifies listeners', () {
      // Same participant set, same mute state, same join times. The predicate
      // this replaced compared the participant SET, which dedups by identity --
      // so a sibling losing its tap point landed in complete silence and the
      // election never re-ran.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.recompute();
      final before = notifications;

      roster.attributes = {
        '$me:MYOTHERPHONE': {CallRoster.canCaptureAttribute: 'no'},
      };
      roster.recompute();

      expect(notifications, greaterThan(before));
      expect(roster.siblingCanCapture('MYOTHERPHONE'), isFalse);
    });
  });

  group('what a device says about whether it IS recording', () {
    test('a device that has published nothing is SILENT', () async {
      // Not a denial. An older build publishes none of this and a device whose
      // write is still on the wire has published none of it yet, and reading
      // either as "it is idle" disqualifies a sibling that may be recording
      // perfectly well -- which is how a duplicate of a held stretch was kept.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.recompute();

      final report = roster.siblingCaptureReport('MYOTHERPHONE');
      expect(report.run, isNull);
      expect(report.denies, isFalse);
    });

    test('a device nobody can see is silent too', () {
      roster.recompute();
      final report = roster.siblingCaptureReport('NEVERHEARDOFIT');
      expect(report.run, isNull);
      expect(report.denies, isFalse);
    });

    test('saying it CAN record is not saying it IS', () async {
      // A device whose tap attached and then delivered nothing goes on
      // advertising "able" until its own watchdog fires; nothing here may turn
      // that into evidence that it recorded anything.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.attributes = {
        '$me:MYOTHERPHONE': {CallRoster.canCaptureAttribute: 'yes'},
      };
      roster.recompute();

      expect(roster.siblingCanCapture('MYOTHERPHONE'), isTrue);
      expect(roster.siblingCaptureReport('MYOTHERPHONE').run, isNull);
    });

    test('a device that names a run is taken at its word', () {
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.attributes = {
        '$me:MYOTHERPHONE': {
          CallRoster.capturingAttribute: CaptureReport.published('3'),
        },
      };
      roster.recompute();

      final report = roster.siblingCaptureReport('MYOTHERPHONE');
      expect(report.run, '3');
      expect(report.deviceId, 'MYOTHERPHONE');
    });

    test('a device that says no is DENYING, which silence is not', () {
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.attributes = {
        '$me:MYOTHERPHONE': {
          CallRoster.capturingAttribute: CaptureReport.published(null),
        },
      };
      roster.recompute();

      expect(roster.siblingCaptureReport('MYOTHERPHONE').denies, isTrue);
    });

    test('a run changing alone notifies listeners', () {
      // Same participant set, same mute state, same join times, same
      // capability. A sibling stopping and restarting is exactly the shape of
      // change the discard now depends on, and the predicate has to see it --
      // the run token is the only trace such a pair leaves.
      roster.identities = {'$me:MYOTHERPHONE'};
      roster.attributes = {
        '$me:MYOTHERPHONE': {
          CallRoster.capturingAttribute: CaptureReport.published('3'),
        },
      };
      roster.recompute();
      final before = notifications;

      roster.attributes = {
        '$me:MYOTHERPHONE': {
          CallRoster.capturingAttribute: CaptureReport.published('4'),
        },
      };
      roster.recompute();

      expect(notifications, greaterThan(before));
      expect(roster.siblingCaptureReport('MYOTHERPHONE').run, '4');
    });
  });

  group('telling the other devices what this one is doing', () {
    test('an idle device SAYS it is idle', () async {
      // The capability attribute can stay silent because silence already means
      // able. This one cannot: silence here means nothing at all, so a device
      // that is not recording has to say so or a sibling cannot tell it from
      // one it has not heard from. One write per device per call.
      await roster.announceCapturing(null);

      expect(roster.published, [
        {CallRoster.capturingAttribute: CaptureReport.published(null)},
      ]);
    });

    test('a recording device names its run', () async {
      await roster.announceCapturing('5');

      expect(roster.published, [
        {CallRoster.capturingAttribute: CaptureReport.published('5')},
      ]);
    });

    test('the same run twice is not written twice', () async {
      await roster.announceCapturing('5');
      await roster.announceCapturing('5');

      expect(roster.published, hasLength(1));
    });

    test('both facts travel in ONE write', () async {
      // `setAttributes` replaces the whole map and the publish merges over the
      // copy it can see, so two announcements in flight at once would each
      // merge over a picture taken before the other landed and one of them
      // would be silently lost.
      final held = Completer<void>();
      roster.holdPublish = held;
      final first = roster.announceCanCapture(false);
      await pumpEventQueue();
      final second = roster.announceCapturing('5');
      held.complete();
      await first;
      await second;

      expect(roster.published, [
        {CallRoster.canCaptureAttribute: 'no'},
        {CallRoster.capturingAttribute: CaptureReport.published('5')},
      ]);
      expect(roster.announcedCanCapture, isFalse);
    });

    test('an outstanding run is re-asserted on the next recompute', () async {
      roster.publishError = StateError('Signal request timed out');
      await roster.announceCapturing('5');
      expect(roster.published, hasLength(1), reason: 'it did not spin');

      roster.publishError = null;
      roster.recompute();
      await pumpEventQueue();

      expect(roster.published, hasLength(2));
      expect(roster.published.last, {
        CallRoster.capturingAttribute: CaptureReport.published('5'),
      });
    });
  });

  group('telling the other devices whether this one can record', () {
    test('nothing is written while there is nothing to say', () async {
      // Siblings already read silence as able, so announcing "able" before
      // anything has gone wrong is a signal round trip that buys nothing.
      await roster.announceCanCapture(true);
      expect(roster.published, isEmpty);
      expect(roster.announcedCanCapture, isTrue);
    });

    test('a cannot is written and remembered', () async {
      await roster.announceCanCapture(false);

      expect(roster.published, [
        {CallRoster.canCaptureAttribute: 'no'},
      ]);
      expect(roster.announcedCanCapture, isFalse);
    });

    test('a write that never reached the wire is not remembered', () async {
      // The REAL publish, against a room with no local participant to publish
      // as -- which is what this looks like before the SFU has answered the
      // join. A silent no-op that returned normally would be indistinguishable
      // from a write that landed, and remembering it as landed means nothing
      // ever comes back to it: this device would stand aside on an answer its
      // siblings never saw.
      final unconnected = CallRoster(room: room, myUserId: me);
      addTearDown(unconnected.dispose);

      await unconnected.announceCanCapture(false);

      expect(
        unconnected.announcedCanCapture,
        isTrue,
        reason: 'what the siblings hold has not changed',
      );
    });

    test('a write that failed leaves the intent outstanding', () async {
      // setAttributes waits five seconds for the SFU and then throws, and
      // completes with an error when the server refuses -- which is what a
      // token minted without the metadata grant looks like from here.
      roster.publishError = StateError('Signal request timed out');

      await roster.announceCanCapture(false);

      expect(roster.announcedCanCapture, isTrue);
      expect(roster.published, hasLength(1), reason: 'it did not spin');
    });

    test(
      'an outstanding intent is re-asserted on the next recompute',
      () async {
        // Level-triggered like everything else here, so the window in which the
        // siblings hold a stale answer closes when the signal recovers rather
        // than lasting the whole call.
        roster.publishError = StateError('Signal request timed out');
        await roster.announceCanCapture(false);
        expect(roster.announcedCanCapture, isTrue);

        roster.publishError = null;
        roster.recompute();
        await pumpEventQueue();

        expect(roster.announcedCanCapture, isFalse);
        expect(roster.published, hasLength(2));
      },
    );

    test('the latest intent wins over a write already in flight', () async {
      // The same rule the memoised stop in the recorder states: a caller whose
      // intent differs from the write already flying must not be dropped in
      // favour of it.
      final held = Completer<void>();
      roster.holdPublish = held;
      final first = roster.announceCanCapture(false);
      await pumpEventQueue();

      roster.holdPublish = null;
      final second = roster.announceCanCapture(true);
      held.complete();
      await first;
      await second;

      expect(
        roster.announcedCanCapture,
        isTrue,
        reason: 'the siblings end up holding what was wanted last',
      );
      expect(roster.published, [
        {CallRoster.canCaptureAttribute: 'no'},
        {CallRoster.canCaptureAttribute: 'yes'},
      ]);
    });
  });
}
