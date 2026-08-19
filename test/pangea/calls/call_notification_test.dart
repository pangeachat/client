import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Client client;
  late Room room;

  setUp(() async {
    client = Client(
      'notification-test',
      httpClient: FakeMatrixApi(),
      database: await MatrixSdkDatabase.init(
        'notification-test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    room = Room(id: '!r:server', client: client);
  });

  final now = DateTime.utc(2026, 8, 18, 12);
  const me = '@learner:server';
  const peer = '@teacher:server';

  Event notification({
    String sender = peer,
    String type = PangeaEventTypes.callNotification,
    Map<String, dynamic>? application,
    Object? relatesTo = const {
      'rel_type': 'm.reference',
      'event_id': '\$membership',
    },
    DateTime? serverTs,
  }) => Event(
    type: type,
    eventId: '\$n',
    senderId: sender,
    originServerTs: serverTs ?? now,
    room: room,
    content: {
      'application':
          application ??
          {
            'type': 'm.call',
            'notification_type': 'ring',
            'sender_ts': now.millisecondsSinceEpoch,
            'lifetime': 30000,
            'm.call.intent': 'audio',
          },
      if (relatesTo != null) ...{'m.relates_to': relatesTo},
    },
  );

  IncomingCallNotification incoming(Event e, {bool joined = false}) =>
      IncomingCallNotification(event: e, myUserId: me, alreadyJoined: joined);

  group('sending', () {
    test('names the call by the sender own membership', () {
      const n = CallNotification(
        membershipEventId: '\$m',
        senderDeviceId: 'CALLERDEVICE',
        video: false,
      );
      final content = n.toContent(now);

      expect(content['m.relates_to'], {
        'rel_type': 'm.reference',
        'event_id': '\$m',
      });
      expect(content['application']['device_id'], 'CALLERDEVICE');
      expect(content['application']['notification_type'], 'ring');
      expect(content['application']['m.call.intent'], 'audio');
      expect(content['application']['lifetime'], 30000);
      expect(content['application']['sender_ts'], now.millisecondsSinceEpoch);
    });

    test('a video call says so', () {
      const n = CallNotification(
        membershipEventId: '\$m',
        senderDeviceId: 'D',
        video: true,
      );
      expect(n.toContent(now)['application']['m.call.intent'], 'video');
    });

    test(
      'mentions the room, which in a direct message is the other person',
      () {
        const n = CallNotification(
          membershipEventId: '\$m',
          senderDeviceId: 'D',
          video: false,
        );
        expect(n.toContent(now)['m.mentions'], {'user_ids': [], 'room': true});
      },
    );
  });

  group('deciding whether to ring', () {
    test('rings for a fresh call from someone else', () {
      expect(incoming(notification()).shouldRing(now), isTrue);
    });

    test('carries which device is calling', () {
      final n = notification(
        application: {
          'type': 'm.call',
          'notification_type': 'ring',
          'sender_ts': now.millisecondsSinceEpoch,
          'lifetime': 30000,
          'device_id': 'THEIRPHONE',
        },
      );
      expect(incoming(n).senderDeviceId, 'THEIRPHONE');
    });

    test('does not ring for a call this account placed', () {
      expect(incoming(notification(sender: me)).shouldRing(now), isFalse);
    });

    test('does not ring for a call already joined', () {
      expect(incoming(notification(), joined: true).shouldRing(now), isFalse);
    });

    test('does not ring after the call stopped ringing', () {
      final late = now.add(const Duration(seconds: 31));
      expect(incoming(notification()).shouldRing(late), isFalse);
    });

    test('does not ring for a notice that asked not to', () {
      final quiet = notification(
        application: {
          'type': 'm.call',
          'notification_type': 'notification',
          'sender_ts': now.millisecondsSinceEpoch,
          'lifetime': 30000,
        },
      );
      expect(incoming(quiet).shouldRing(now), isFalse);
    });

    test('does not ring for one that names no call', () {
      expect(incoming(notification(relatesTo: null)).shouldRing(now), isFalse);
      final wrongRelation = notification(
        relatesTo: const {'rel_type': 'm.annotation', 'event_id': '\$m'},
      );
      expect(incoming(wrongRelation).shouldRing(now), isFalse);
    });

    test('does not ring for some other kind of event', () {
      expect(
        incoming(notification(type: 'm.room.message')).shouldRing(now),
        isFalse,
      );
    });
  });

  group('how long it rings', () {
    test('honours what the sender asked for', () {
      expect(incoming(notification()).lifetime, const Duration(seconds: 30));
    });

    test('caps a sender asking for too long', () {
      // Ninety seconds is what the shipped implementations enforce. Following
      // them rather than the proposal's two minutes keeps a Matrix peer and
      // this client agreeing about when a call stopped ringing.
      final greedy = notification(
        application: {
          'type': 'm.call',
          'notification_type': 'ring',
          'sender_ts': now.millisecondsSinceEpoch,
          'lifetime': 600000,
        },
      );
      expect(incoming(greedy).lifetime, CallNotification.maxLifetime);
    });

    test('a negative lifetime rings for no time at all', () {
      final odd = notification(
        application: {
          'type': 'm.call',
          'notification_type': 'ring',
          'sender_ts': now.millisecondsSinceEpoch,
          'lifetime': -5000,
        },
      );
      expect(incoming(odd).lifetime, Duration.zero);
      expect(incoming(odd).shouldRing(now), isFalse);
    });

    test('a missing lifetime falls back to the usual one', () {
      final bare = notification(
        application: {
          'type': 'm.call',
          'notification_type': 'ring',
          'sender_ts': now.millisecondsSinceEpoch,
        },
      );
      expect(incoming(bare).lifetime, CallNotification.lifetime);
    });
  });

  group('a notification from another kind of session', () {
    test('does not ring', () {
      // The proposal carries every MatrixRTC application through this one
      // event, and any of them may ask to ring. A whiteboard announcing itself
      // would otherwise put a call card on the learner's screen.
      final whiteboard = notification(
        application: {
          'type': 'm.whiteboard',
          'notification_type': 'ring',
          'sender_ts': now.millisecondsSinceEpoch,
          'lifetime': 30000,
        },
      );
      expect(incoming(whiteboard).shouldRing(now), isFalse);
    });
  });

  group('a sender whose clock is wrong', () {
    test('is believed when it is close enough', () {
      final slightlyOff = notification(
        application: {
          'type': 'm.call',
          'notification_type': 'ring',
          'sender_ts': now
              .add(const Duration(seconds: 5))
              .millisecondsSinceEpoch,
          'lifetime': 30000,
        },
      );
      expect(
        incoming(slightlyOff).sentAt.millisecondsSinceEpoch,
        now.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
      );
    });

    test('is disbelieved when it is far out, and the server is used', () {
      // A device days ahead would otherwise make its call ring forever, and one
      // days behind would make every call arrive already expired.
      final wayOff = notification(
        application: {
          'type': 'm.call',
          'notification_type': 'ring',
          'sender_ts': now.add(const Duration(days: 2)).millisecondsSinceEpoch,
          'lifetime': 30000,
        },
      );
      expect(
        incoming(wayOff).sentAt.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
      expect(incoming(wayOff).shouldRing(now), isTrue);
    });
  });
}
