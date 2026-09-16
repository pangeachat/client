import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/notifications/background_push_notification.dart';
import 'package:fluffychat/utils/init_with_restore.dart';

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
}
