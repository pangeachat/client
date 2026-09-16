import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/notifications/background_push_notification.dart';
import 'package:fluffychat/l10n/l10n.dart';
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
}
