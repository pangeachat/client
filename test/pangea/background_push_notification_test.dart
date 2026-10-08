import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:pangea_call_capture/pangea_call_capture.dart';

import 'package:fluffychat/features/notifications/background_push_notification.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/push_helper.dart';

const _roomId = '!room:staging.pangea.chat';
const _sender = '@teacher:staging.pangea.chat';

const _session = SessionBackup(
  olmAccount: null,
  accessToken: 'syt_secret_token',
  userId: '@learner:staging.pangea.chat',
  homeserver: 'https://matrix.staging.pangea.chat/',
  deviceId: 'DEVICE',
);

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

/// A homeserver whose room-avatar state read answers [roomState], whose sender
/// profile carries [senderAvatar], and which serves image bytes for anything
/// else. Every request is recorded in [requests].
MockClient _server({
  required List<http.BaseRequest> requests,
  http.Response? roomState,
  String? senderAvatar = 'mxc://staging.pangea.chat/sender',
}) => MockClient((request) async {
  requests.add(request);
  final path = request.url.path;
  if (path.endsWith('/state/m.room.avatar')) {
    if (roomState == null) throw http.ClientException('offline');
    return roomState;
  }
  if (path.endsWith('/avatar_url')) {
    return http.Response(jsonEncode({'avatar_url': senderAvatar}), 200);
  }
  return http.Response.bytes(_png, 200);
});

http.Response _roomAvatar(String url) =>
    http.Response(jsonEncode({'url': url}), 200);

/// A ring from the teacher, as the homeserver returns it.
Map<String, Object?> _ringEvent({
  required DateTime sentAt,
  String intent = 'audio',
  int lifetimeMs = 30000,
}) => {
  'type': PangeaEventTypes.callNotification,
  'event_id': r'$ring',
  'room_id': _roomId,
  'sender': _sender,
  'origin_server_ts': sentAt.millisecondsSinceEpoch,
  'content': {
    'application': {
      'type': 'm.call',
      'notification_type': 'ring',
      'sender_ts': sentAt.millisecondsSinceEpoch,
      'lifetime': lifetimeMs,
      'm.call.intent': intent,
    },
    'm.relates_to': {'rel_type': 'm.reference', 'event_id': r'$membership'},
  },
};

Iterable<String> _paths(List<http.BaseRequest> requests) =>
    requests.map((r) => r.url.path);

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await lookupL10n(const Locale('en'));
  });

  test('a room avatar is fetched as an authenticated mxc thumbnail', () async {
    final requests = <http.BaseRequest>[];
    final avatar = await BackgroundPushNotification.avatarForTesting(
      _server(
        requests: requests,
        roomState: _roomAvatar('mxc://staging.pangea.chat/abc123'),
      ),
      [_session],
      roomId: _roomId,
      sender: _sender,
    );

    expect(avatar, _png);
    final thumbnail = requests.last;
    expect(
      thumbnail.url.path,
      '/_matrix/client/v1/media/thumbnail/staging.pangea.chat/abc123',
    );
    expect(thumbnail.headers['Authorization'], 'Bearer syt_secret_token');
    // A room avatar was found, so the sender profile is never consulted.
    expect(_paths(requests).any((p) => p.endsWith('/avatar_url')), isFalse);
  });

  test(
    'an allow-listed https avatar is fetched WITHOUT the access token',
    () async {
      // The allow-list includes third parties such as img.youtube.com. Sending the
      // Matrix token with this request would leak a user's credential.
      final requests = <http.BaseRequest>[];
      final avatar = await BackgroundPushNotification.avatarForTesting(
        _server(
          requests: requests,
          roomState: _roomAvatar(
            'https://content.pangea.chat/avatars/course.png',
          ),
        ),
        [_session],
        roomId: _roomId,
      );

      expect(avatar, _png);
      final download = requests.last;
      expect(download.url.host, 'content.pangea.chat');
      expect(download.headers.containsKey('Authorization'), isFalse);
    },
  );

  test('an https avatar outside the allow-list is never requested', () async {
    final requests = <http.BaseRequest>[];
    final avatar = await BackgroundPushNotification.avatarForTesting(
      _server(
        requests: requests,
        roomState: _roomAvatar('https://evil.example/avatar.png'),
      ),
      [_session],
      roomId: _roomId,
    );

    expect(avatar, isNull);
    expect(requests.any((r) => r.url.host == 'evil.example'), isFalse);
  });

  test('a direct chat (404) falls back to the sender avatar, as on iOS', () async {
    final requests = <http.BaseRequest>[];
    final avatar = await BackgroundPushNotification.avatarForTesting(
      _server(
        requests: requests,
        roomState: http.Response('{"errcode":"M_NOT_FOUND"}', 404),
      ),
      [_session],
      roomId: _roomId,
      sender: _sender,
    );

    expect(avatar, _png);
    expect(_paths(requests), [
      '/_matrix/client/v3/rooms/!room%3Astaging.pangea.chat/state/m.room.avatar',
      '/_matrix/client/v3/profile/%40teacher%3Astaging.pangea.chat/avatar_url',
      '/_matrix/client/v1/media/thumbnail/staging.pangea.chat/sender',
    ]);
  });

  test(
    'an unaccepted invite (403) still falls back to the sender avatar, as on iOS',
    () async {
      // 403 means no account has joined the room yet. iOS falls back to the
      // sender on any missing room avatar; the profile needs no membership, so
      // Android must do the same rather than give up on the account.
      final requests = <http.BaseRequest>[];
      final avatar = await BackgroundPushNotification.avatarForTesting(
        _server(
          requests: requests,
          roomState: http.Response('{"errcode":"M_FORBIDDEN"}', 403),
        ),
        [_session],
        roomId: _roomId,
        sender: _sender,
      );

      expect(avatar, _png);
      expect(_paths(requests).any((p) => p.endsWith('/avatar_url')), isTrue);
    },
  );

  test('a failed room lookup still falls back to the sender avatar', () async {
    final requests = <http.BaseRequest>[];
    final avatar = await BackgroundPushNotification.avatarForTesting(
      _server(requests: requests),
      [_session],
      roomId: _roomId,
      sender: _sender,
    );

    expect(avatar, _png);
  });

  test(
    'no room avatar and no sender avatar yields no avatar, not an error',
    () async {
      final avatar = await BackgroundPushNotification.avatarForTesting(
        _server(
          requests: [],
          roomState: http.Response('{"errcode":"M_NOT_FOUND"}', 404),
          senderAvatar: null,
        ),
        [_session],
        roomId: _roomId,
        sender: _sender,
      );

      expect(avatar, isNull);
    },
  );

  test(
    'an expired token (401) moves on to the next account instead of stopping',
    () async {
      // A backup written before the running app refreshed its token gets 401.
      // That proves nothing about membership, so the account that CAN read the
      // room must still be found and its token used for the thumbnail.
      const stale = SessionBackup(
        olmAccount: null,
        accessToken: 'syt_expired',
        userId: '@other:staging.pangea.chat',
        homeserver: 'https://matrix.staging.pangea.chat',
        deviceId: 'OTHER',
      );
      final requests = <http.BaseRequest>[];
      final avatar = await BackgroundPushNotification.avatarForTesting(
        MockClient((request) async {
          requests.add(request);
          if (request.headers['Authorization'] == 'Bearer syt_expired') {
            return http.Response('{"errcode":"M_UNKNOWN_TOKEN"}', 401);
          }
          if (request.url.path.endsWith('/state/m.room.avatar')) {
            return _roomAvatar('mxc://staging.pangea.chat/abc123');
          }
          return http.Response.bytes(_png, 200);
        }),
        [stale, _session],
        roomId: _roomId,
        sender: _sender,
      );

      expect(avatar, _png);
      expect(requests.last.headers['Authorization'], 'Bearer syt_secret_token');
    },
  );

  group('bodyFor', () {
    Map<String, dynamic> invite({String? reason}) => {
      'type': 'm.room.member',
      'content_membership': 'invite',
      'sender': _sender,
      'sender_display_name': 'Teacher',
      'content_reason': ?reason,
    };

    test('an invite names the inviter, as Sygnal did', () {
      expect(
        BackgroundPushNotification.bodyFor(invite(), l10n),
        l10n.youInvitedBy('Teacher'),
      );
    });

    test('an invite that accepts a knock says the request was accepted', () {
      expect(
        BackgroundPushNotification.bodyFor(
          invite(reason: 'invite_on_knock'),
          l10n,
        ),
        l10n.knockAccepted,
      );
    });

    test('a message shows its body', () {
      expect(
        BackgroundPushNotification.bodyFor({
          'type': 'm.room.message',
          'content_body': 'Join my activity!',
        }, l10n),
        'Join my activity!',
      );
    });

    test('a message without a body asks to open the app', () {
      expect(
        BackgroundPushNotification.bodyFor({'type': 'm.room.message'}, l10n),
        l10n.openAppToReadMessages,
      );
    });

    test('a ring says what kind of call it is', () {
      const push = {'type': PangeaEventTypes.callNotification};
      IncomingRing ring(String intent) => IncomingRing(
        event: MatrixEvent.fromJson(
          _ringEvent(sentAt: DateTime.now(), intent: intent),
        ),
        myUserId: _session.userId,
        alreadyJoined: false,
      );
      expect(
        BackgroundPushNotification.bodyFor(push, l10n, ring('audio')),
        l10n.callIncomingVoice,
      );
      expect(
        BackgroundPushNotification.bodyFor(push, l10n, ring('video')),
        l10n.callIncomingVideo,
      );
      // Unread, it is still a call, never "open the app to read messages".
      expect(BackgroundPushNotification.bodyFor(push, l10n), l10n.callIncoming);
    });
  });

  group('reading a ring back', () {
    Future<IncomingRing?> read(http.Response response) async {
      final requests = <http.BaseRequest>[];
      final ring = await BackgroundPushNotification.ringForTesting(
        MockClient((request) async {
          requests.add(request);
          return response;
        }),
        _session,
        roomId: _roomId,
        eventId: r'$ring',
      );
      expect(requests.single.url.pathSegments.skip(3), [
        'rooms',
        _roomId,
        'event',
        r'$ring',
      ]);
      expect(
        requests.single.headers['Authorization'],
        'Bearer syt_secret_token',
      );
      return ring;
    }

    test('a live ring rings', () async {
      final ring = await read(
        http.Response(jsonEncode(_ringEvent(sentAt: DateTime.now())), 200),
      );
      expect(ring?.shouldRing(DateTime.now()), isTrue);
    });

    test('a ring that has ended does not', () async {
      final ring = await read(
        http.Response(
          jsonEncode(
            _ringEvent(
              sentAt: DateTime.now().subtract(const Duration(minutes: 2)),
            ),
          ),
          200,
        ),
      );
      expect(ring?.shouldRing(DateTime.now()), isFalse);
    });

    // Unreadable is not "over": the caller decides to show the notification.
    test('a ring the server will not return is unknown', () async {
      expect(await read(http.Response('{}', 404)), isNull);
    });

    test('a ring the server returns garbled is unknown', () async {
      expect(await read(http.Response('not json', 200)), isNull);
    });
  });

  test('a payload value containing | still routes a course ping tap', () {
    // Closed-app taps now route through this string, so a ping whose body
    // contains '|' must keep its activity session keys.
    final additionalData = {
      'content_body': 'Level 1 | Ordering food',
      'content_pangea.activity.session_room_id': '!session:staging.pangea.chat',
      'content_pangea.activity.id': 'activity-123',
    };
    final parsed = FluffyChatPushPayload.fromString(
      FluffyChatPushPayload(
        'client',
        _roomId,
        r'$event',
        additionalData: additionalData,
      ).toString(),
    );

    expect(parsed.roomId, _roomId);
    expect(parsed.eventId, r'$event');
    expect(parsed.additionalData, additionalData);
  });

  group('ringing while the app is closed', () {
    const every = Duration(milliseconds: 10);

    IncomingRing ringFor({int lifetimeMs = 30000}) => IncomingRing(
      event: MatrixEvent.fromJson(
        _ringEvent(
          sentAt: DateTime.now().subtract(const Duration(seconds: 1)),
          lifetimeMs: lifetimeMs,
        ),
      ),
      myUserId: _session.userId,
      alreadyJoined: false,
    );

    // Long enough that a watcher which missed the signal and rang out its
    // lifetime fails the timing checks below rather than passing slowly.
    Future<bool> ringAndWatch(
      _Homeserver server,
      _FakeRinger ringer, {
      int lifetimeMs = 5000,
    }) => BackgroundPushNotification.ringAndWatchForTesting(
      MockClient(server.answer),
      _session,
      ringFor(lifetimeMs: lifetimeMs),
      roomId: _roomId,
      ringer: ringer,
      every: every,
    );

    test('rings, then stops when the caller gives up', () async {
      final server = _Homeserver(
        states: [
          [_member(_sender)],
          [_member(_sender, live: false)],
        ],
      );
      final ringer = _FakeRinger();
      final started = DateTime.now();
      expect(await ringAndWatch(server, ringer), isTrue);
      expect(ringer.rang, [r'$ring']);
      expect(ringer.stopped, [r'$ring']);
      expect(DateTime.now().difference(started), lessThan(seconds(2)));
    });

    test('stops when another of my devices answers', () async {
      final server = _Homeserver(
        states: [
          [_member(_sender)],
          [_member(_sender), _member(_session.userId, device: 'LAPTOP')],
        ],
      );
      final ringer = _FakeRinger();
      final started = DateTime.now();
      await ringAndWatch(server, ringer);
      expect(ringer.stopped, [r'$ring']);
      expect(DateTime.now().difference(started), lessThan(seconds(2)));
    });

    test('stops when another of my devices declines', () async {
      final server = _Homeserver(
        states: [
          [_member(_sender)],
        ],
        declines: [
          [],
          [_decline(r'$ring')],
        ],
      );
      final ringer = _FakeRinger();
      final started = DateTime.now();
      await ringAndWatch(server, ringer);
      expect(ringer.stopped, [r'$ring']);
      expect(DateTime.now().difference(started), lessThan(seconds(2)));
    });

    test('a decline from the notification tells the caller', () async {
      final server = _Homeserver(
        states: [
          [_member(_sender)],
        ],
      );
      final ringer = _FakeRinger(outcomes: [RingOutcome.declined]);
      await ringAndWatch(server, ringer);
      final sent = server.sent.single;
      expect(sent.url.pathSegments.skip(3).take(4), [
        'rooms',
        _roomId,
        'send',
        PangeaEventTypes.callDecline,
      ]);
      expect(
        jsonDecode(sent.body),
        jsonDecode(jsonEncode(CallService.declineContent(r'$ring'))),
      );
      // The platform stopped ringing the moment the button was pressed.
      expect(ringer.stopped, isEmpty);
    });

    test('an answer from the notification is left to the app', () async {
      final server = _Homeserver(
        states: [
          [_member(_sender)],
        ],
      );
      final ringer = _FakeRinger(outcomes: [RingOutcome.answered]);
      await ringAndWatch(server, ringer);
      expect(server.sent, isEmpty);
      expect(ringer.stopped, isEmpty);
    });

    test('a call already over does not ring at all', () async {
      final server = _Homeserver(
        states: [
          [_member(_sender, live: false)],
        ],
      );
      final ringer = _FakeRinger();
      expect(await ringAndWatch(server, ringer), isTrue);
      expect(ringer.rang, isEmpty);
    });

    test('a call answered elsewhere before the push does not ring', () async {
      final server = _Homeserver(
        states: [
          [_member(_sender), _member(_session.userId, device: 'LAPTOP')],
        ],
      );
      final ringer = _FakeRinger();
      await ringAndWatch(server, ringer);
      expect(ringer.rang, isEmpty);
    });

    test('a refused ring falls back to an ordinary notification', () async {
      final server = _Homeserver(
        states: [
          [_member(_sender)],
        ],
      );
      expect(await ringAndWatch(server, _FakeRinger(refuses: true)), isFalse);
    });

    // A read that fails proves nothing, so the phone rings on -- but never
    // past the ring's own lifetime.
    test('rings through failed reads until its lifetime, then stops', () async {
      final server = _Homeserver(states: const [], failing: true);
      final ringer = _FakeRinger();
      final started = DateTime.now();
      await ringAndWatch(server, ringer, lifetimeMs: 1300);
      expect(ringer.rang, [r'$ring']);
      expect(ringer.stopped, [r'$ring']);
      expect(DateTime.now().difference(started), lessThan(seconds(3)));
    });
  });
}

Duration seconds(int n) => Duration(seconds: n);

/// A caller's or a learner's call membership, written now.
Map<String, Object?> _member(
  String sender, {
  String device = 'CALLERPHONE',
  bool live = true,
}) {
  final at = DateTime.now().millisecondsSinceEpoch;
  return {
    'type': EventTypes.GroupCallMember,
    'state_key': '_${sender}_$device',
    'sender': sender,
    'event_id': '\$member-$sender-$device-$live',
    'origin_server_ts': at,
    'content': {
      'memberships': [
        if (live)
          {
            'device_id': device,
            'call_id': '',
            'expires_ts': at + const Duration(hours: 4).inMilliseconds,
          },
      ],
    },
  };
}

/// A decline the learner sent from another device.
Map<String, Object?> _decline(String ringId) => {
  'type': PangeaEventTypes.callDecline,
  'event_id': '\$decline',
  'sender': _session.userId,
  'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
  'content': CallService.declineContent(ringId),
};

/// Answers the watcher's reads from scripts, one entry per read and the last
/// entry repeated, and records what it sends.
class _Homeserver {
  final List<List<Map<String, Object?>>> states;
  final List<List<Map<String, Object?>>> declines;
  final bool failing;
  final sent = <http.Request>[];
  var _stateReads = 0;
  var _declineReads = 0;

  _Homeserver({
    required this.states,
    this.declines = const [],
    this.failing = false,
  });

  static T _next<T>(List<T> script, int read, T otherwise) =>
      script.isEmpty ? otherwise : script[read.clamp(0, script.length - 1)];

  Future<http.Response> answer(http.Request request) async {
    if (failing) return http.Response('', 502);
    final path = request.url.path;
    if (request.method == 'PUT') {
      sent.add(request);
      return http.Response(jsonEncode({'event_id': r'$sent'}), 200);
    }
    if (path.endsWith('/state')) {
      return http.Response(
        jsonEncode(_next(states, _stateReads++, const [])),
        200,
      );
    }
    if (path.endsWith('/messages')) {
      return http.Response(
        jsonEncode({'chunk': _next(declines, _declineReads++, const [])}),
        200,
      );
    }
    return http.Response('', 404);
  }
}

class _FakeRinger implements IncomingCallRinger {
  final bool refuses;
  final List<RingOutcome?> outcomes;
  final rang = <String>[];
  final stopped = <String>[];
  var _asked = 0;

  _FakeRinger({this.refuses = false, this.outcomes = const []});

  @override
  Future<bool> ring({
    required String ringId,
    required String caller,
    required bool video,
    required DateTime expiresAt,
    required String channelName,
    required String payload,
  }) async {
    if (refuses) return false;
    rang.add(ringId);
    return true;
  }

  @override
  Future<RingOutcome?> outcome(String ringId) async =>
      _Homeserver._next(outcomes, _asked++, RingOutcome.ringing);

  @override
  Future<void> stop(String ringId) async => stopped.add(ringId);

  @override
  void onAnswered(void Function(String payload) handle) {}
}
