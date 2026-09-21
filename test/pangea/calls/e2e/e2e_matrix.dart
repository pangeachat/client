// The thinnest Matrix client the round-trip test needs.
//
// Deliberately raw HTTP rather than the SDK: the point of that test is to
// exercise OUR writer and reader against a real server, so the fewer layers
// between them and the wire, the less a green result can be hiding.

import 'dart:convert';
import 'dart:io';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_writer.dart';

class E2eMatrix {
  final String homeserver;
  final String userId;
  final String _token;
  final HttpClient _http = HttpClient();

  E2eMatrix._(this.homeserver, this.userId, this._token);

  static Future<E2eMatrix> login(
    String homeserver,
    String user,
    String password,
  ) async {
    final body = await _post(homeserver, '/_matrix/client/v3/login', null, {
      'type': 'm.login.password',
      'identifier': {'type': 'm.id.user', 'user': user},
      'password': password,
    });
    final token = body['access_token'];
    final id = body['user_id'];
    if (token is! String || id is! String) {
      throw StateError('could not log in as $user: $body');
    }
    return E2eMatrix._(homeserver, id, token);
  }

  Future<String> createRoom(String name) async {
    final body = await _post(
      homeserver,
      '/_matrix/client/v3/createRoom',
      _token,
      {'preset': 'private_chat', 'name': name},
    );
    return body['room_id'] as String;
  }

  Future<void> invite(String roomId, String who) => _post(
    homeserver,
    '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/invite',
    _token,
    {'user_id': who},
  );

  Future<void> join(String roomId) => _post(
    homeserver,
    '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/join',
    _token,
    const {},
  );

  Future<void> leave(String roomId) => _post(
    homeserver,
    '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/leave',
    _token,
    const {},
  );

  /// A membership STATE event id from this room — the same shape as a real
  /// call_key, which is what makes this test worth running at all.
  Future<String> firstMemberEventId(String roomId) async {
    final body = await _get(
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}'
      '/messages?dir=b&limit=50',
    );
    for (final event in (body['chunk'] as List)) {
      if (event['type'] == 'm.room.member') return event['event_id'] as String;
    }
    throw StateError('no membership event in $roomId');
  }

  /// A fresh anchor, so each test owns its own call rather than inheriting the
  /// halves an earlier one wrote to the same key.
  Future<String> sendMarker(String roomId) async {
    final body = await _put(
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}'
      '/send/pangea.call/${DateTime.now().microsecondsSinceEpoch}',
      const {'msgtype': 'pangea.call', 'body': 'anchor'},
    );
    return body['event_id'] as String;
  }

  /// The real writer's send hook, pointed at this room.
  TranscriptSender sender(
    String roomId,
    String eventType,
  ) => (content, txnId) async {
    await _put(
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}'
      '/send/${Uri.encodeComponent(eventType)}/${Uri.encodeComponent(txnId)}',
      content,
    );
  };

  /// The real reader's fetch hook, hitting the actual relations endpoint.
  RelationsFetcher relationsFetcher() =>
      ({
        required String roomId,
        required String eventId,
        required String relType,
        String? from,
      }) async {
        final query = from == null ? '' : '?from=${Uri.encodeComponent(from)}';
        final body = await _get(
          '/_matrix/client/v1/rooms/${Uri.encodeComponent(roomId)}'
          '/relations/${Uri.encodeComponent(eventId)}'
          '/${Uri.encodeComponent(relType)}$query',
        );
        return (
          chunk: [
            for (final raw in (body['chunk'] as List))
              MatrixEvent.fromJson(raw as Map<String, Object?>),
          ],
          nextBatch: body['next_batch'] as String?,
        );
      };

  Future<Map<String, dynamic>> _get(String path) async {
    final request = await _http.getUrl(Uri.parse('$homeserver$path'));
    request.headers.set('authorization', 'Bearer $_token');
    return _read(await request.close(), path);
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final request = await _http.putUrl(Uri.parse('$homeserver$path'));
    request.headers
      ..set('authorization', 'Bearer $_token')
      ..contentType = ContentType.json;
    request.write(jsonEncode(body));
    return _read(await request.close(), path);
  }

  static Future<Map<String, dynamic>> _post(
    String homeserver,
    String path,
    String? token,
    Map<String, dynamic> body,
  ) async {
    final http = HttpClient();
    try {
      final request = await http.postUrl(Uri.parse('$homeserver$path'));
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      return _read(await request.close(), path);
    } finally {
      http.close();
    }
  }

  static Future<Map<String, dynamic>> _read(
    HttpClientResponse response,
    String path,
  ) async {
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      // Surfaced with the body: a Matrix error says WHY, and swallowing it
      // turns a clear server refusal into an unexplained test failure.
      throw StateError('$path -> ${response.statusCode}: $text');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }
}
