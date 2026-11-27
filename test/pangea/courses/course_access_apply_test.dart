import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_access/course_access.dart';
import 'package:fluffychat/features/course_access/course_access_room_extension.dart';
import '../get_test_client.dart';

/// Applying a course access setting writes the join rule before the directory
/// listing, so a failed second write never leaves a course listed in search
/// with a join rule nobody chose (joining-courses.instructions.md § Course
/// access).
void main() {
  const roomId = '!course:fakeServer.notExisting';

  late _AccessServer server;
  late Client client;
  late Room room;

  setUp(() async {
    server = _AccessServer();
    client = await getTestClient(httpClient: server);
    room = Room(id: roomId, client: client);
    room.setState(
      Event(
        type: EventTypes.RoomJoinRules,
        content: {'join_rule': 'knock', 'access_code': 'abc1234'},
        senderId: '@test:fakeServer.notExisting',
        eventId: '\$rules',
        originServerTs: DateTime.utc(2026, 1, 1),
        stateKey: '',
        room: room,
      ),
    );
  });

  tearDown(() => client.dispose());

  test('the join rule is written before the directory listing', () async {
    await room.setCourseAccess(CourseAccess.public);

    expect(server.writes, ['join_rules', 'directory']);
    expect(server.joinRuleBody?['join_rule'], 'public');
    expect(
      server.joinRuleBody?['access_code'],
      'abc1234',
      reason: 'the course keeps its code',
    );
  });

  test('a failed join rule write leaves the listing unchanged', () async {
    server.failJoinRules = true;

    await expectLater(
      room.setCourseAccess(CourseAccess.public),
      throwsA(isA<Exception>()),
    );
    expect(server.writes, ['join_rules']);
  });

  test('a setting with the same join rule writes only the listing', () async {
    await room.setCourseAccess(CourseAccess.approvalRequired);

    expect(server.writes, ['directory']);
  });
}

/// Answers the two access writes itself and records them in order; everything
/// else goes to [FakeMatrixApi].
class _AccessServer extends http.BaseClient {
  final FakeMatrixApi _fallback = FakeMatrixApi();
  final List<String> writes = [];
  Map<String, dynamic>? joinRuleBody;
  bool failJoinRules = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = Uri.decodeFull(request.url.path);
    if (request.method == 'PUT' && path.contains('/state/m.room.join_rules')) {
      writes.add('join_rules');
      if (failJoinRules) {
        return _json({'errcode': 'M_UNKNOWN', 'error': 'down'}, 500);
      }
      joinRuleBody = jsonDecode((request as http.Request).body);
      return _json({'event_id': '\$new'});
    }
    if (request.method == 'PUT' && path.contains('/directory/list/room/')) {
      writes.add('directory');
      return _json({});
    }
    return _fallback.send(request);
  }

  http.StreamedResponse _json(Map<String, dynamic> body, [int status = 200]) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
}
