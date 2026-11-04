import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/discussions/discussion_room_repo.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../activity_session_fixtures.dart';
import '../get_test_client.dart';

/// The client side of synapse's `discussion_room` endpoint (#9647): a 404
/// from the preview is an answer ("this course doesn't list it"), every other
/// failure is an error, and ending or reopening a seat names only the room
/// and the action, so the server writes the one seat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const path = '/_synapse/client/pangea/v1/discussion_room';
  const courseId = '!course:fakeServer.notExisting';
  const activityId = 'discussion-1';
  const roomId = '!discussion:fakeServer.notExisting';

  late Client client;
  late List<http.Request> sent;
  late http.Response Function(http.Request) answer;
  late _DiscussionRoomServer server;

  setUpAll(() async {
    // A discussion room is one the bot created.
    dotenv.testLoad(fileInput: 'BOT_NAME=$testDiscussionBotId');
    final tempDir = await Directory.systemTemp.createTemp('discussion_repo');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async {
    sent = [];
    answer = (_) => http.Response('{}', 200);
    server = _DiscussionRoomServer(path, (request) {
      sent.add(request);
      return answer(request);
    });
    client = await getTestClient(httpClient: server);
  });

  tearDown(() async {
    await client.dispose();
  });

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  group('previewStudents', () {
    test('answers the classmate count, asking with the course and '
        'activity', () async {
      answer = (_) => json({'students': 3});
      final result = await DiscussionRoomRepo.previewStudents(
        client,
        courseId: courseId,
        activityId: activityId,
      );
      expect(result.asValue?.value, 3);
      expect(sent.single.method, 'GET');
      expect(sent.single.url.queryParameters, {
        'course_id': courseId,
        'activity_id': activityId,
      });
    });

    test('a 404 is an answer and reports nothing; another failure is an '
        'error, reported once', () async {
      const key = 'discussion_room_preview';
      answer = (_) => json({'errcode': 'M_NOT_FOUND'}, 404);
      final notListed = await DiscussionRoomRepo.previewStudents(
        client,
        courseId: courseId,
        activityId: activityId,
      );
      expect(notListed.isValue, isTrue);
      expect(notListed.asValue!.value, isNull);
      expect(ErrorHandler.reportedOnceKeysForTest, isNot(contains(key)));

      answer = (_) => json({'errcode': 'M_UNKNOWN'}, 500);
      final failed = await DiscussionRoomRepo.previewStudents(
        client,
        courseId: courseId,
        activityId: activityId,
      );
      expect(failed.isError, isTrue);
      expect(failed.asError!.error, isA<PangeaHttpException>());
      expect(ErrorHandler.reportedOnceKeysForTest, contains(key));
    });

    test('an answer without a count is an error', () async {
      answer = (_) => json({'room_id': roomId});
      final result = await DiscussionRoomRepo.previewStudents(
        client,
        courseId: courseId,
        activityId: activityId,
      );
      expect(result.isError, isTrue);
      expect(result.asError!.error, isA<FormatException>());
    });
  });

  group('join', () {
    test('a room the learner is already in opens at once, with the version '
        'they were shown', () async {
      client.rooms.add(
        Room(id: roomId, client: client, membership: Membership.join),
      );
      answer = (_) => json({'room_id': roomId});
      final result = await DiscussionRoomRepo.join(
        client,
        courseId: courseId,
        activityId: activityId,
        versionId: 'v-7',
      );
      expect(result.asValue?.value, roomId);
      expect(sent.single.method, 'POST');
      expect(jsonDecode(sent.single.body), {
        'course_id': courseId,
        'activity_id': activityId,
        'version_id': 'v-7',
      });
    });

    test('a 404 is an error: Join was offered for a discussion the course '
        'does not list', () async {
      answer = (_) => json({'errcode': 'M_NOT_FOUND'}, 404);
      final result = await DiscussionRoomRepo.join(
        client,
        courseId: courseId,
        activityId: activityId,
      );
      expect(result.isError, isTrue);
      expect(PangeaHttpException.statusCodeOf(result.asError!.error), 404);
    });

    test('an answer without a room is an error', () async {
      answer = (_) => json({});
      final result = await DiscussionRoomRepo.join(
        client,
        courseId: courseId,
        activityId: activityId,
      );
      expect(result.asError?.error, isA<FormatException>());
    });
  });

  group('setSeatEnded', () {
    test('"I\'m done" and "Wait, I\'m not done" send only the room and the '
        'action', () async {
      final done = await DiscussionRoomRepo.setSeatEnded(
        client,
        roomId: roomId,
        ended: true,
      );
      final back = await DiscussionRoomRepo.setSeatEnded(
        client,
        roomId: roomId,
        ended: false,
      );
      expect(done.isValue, isTrue);
      expect(back.isValue, isTrue);
      expect(sent.map((r) => r.method), ['POST', 'POST']);
      expect(sent.map((r) => jsonDecode(r.body)), [
        {'room_id': roomId, 'action': 'end'},
        {'room_id': roomId, 'action': 'continue'},
      ]);
    });

    test('a 403 (no seat there) is an error', () async {
      answer = (_) => json({'errcode': 'M_FORBIDDEN'}, 403);
      final result = await DiscussionRoomRepo.setSeatEnded(
        client,
        roomId: roomId,
        ended: true,
      );
      expect(result.isError, isTrue);
      expect(PangeaHttpException.statusCodeOf(result.asError!.error), 403);
    });
  });

  group('ending a seat in a discussion room', () {
    List<http.BaseRequest> roleWrites() => server.roleWrites;

    test('"I\'m done" and "Wait, I\'m not done" ask the server and never '
        'write the room\'s seats', () async {
      final room = discussionRoom(
        client,
        roomId: roomId,
        seats: [discussionSeat(testSessionUserId)],
      );
      client.rooms.add(room);

      await room.finishActivity();
      // Ending mutes the room for the learner.
      expect(server.pushRuleWrites, isNotEmpty);
      await room.continueActivity();

      expect(sent.map((r) => jsonDecode(r.body)), [
        {'room_id': roomId, 'action': 'end'},
        {'room_id': roomId, 'action': 'continue'},
      ]);
      expect(roleWrites(), isEmpty);
    });

    test('a roleplay still writes its own seat (the check above can see a '
        'write)', () async {
      final room = activitySessionRoom(
        client,
        roles: {'r1': ActivityRoleModel(id: 'r1', userId: testSessionUserId)},
      );
      await room.finishActivity();
      expect(sent, isEmpty);
      expect(roleWrites(), hasLength(1));
    });

    test('a failed end is the caller\'s to show', () async {
      final room = discussionRoom(
        client,
        roomId: roomId,
        seats: [discussionSeat(testSessionUserId)],
      );
      answer = (_) => json({'errcode': 'M_FORBIDDEN'}, 403);
      await expectLater(
        room.finishActivity(),
        throwsA(isA<PangeaHttpException>()),
      );
    });

    test('without a seat nothing is sent', () async {
      final room = discussionRoom(
        client,
        roomId: roomId,
        seats: [discussionSeat('@classmate:fakeServer.notExisting')],
      );
      await room.finishActivity();
      expect(sent, isEmpty);
    });
  });
}

/// Answers the discussion endpoint with [handle], records and accepts a
/// write of a room's seats ([roleWrites]) or its notifications
/// ([pushRuleWrites]), and passes everything else (login)
/// to a [FakeMatrixApi].
class _DiscussionRoomServer extends http.BaseClient {
  final String path;
  final http.Response Function(http.Request) handle;
  final FakeMatrixApi _matrix = FakeMatrixApi();
  final List<http.BaseRequest> roleWrites = [];

  /// The room's notification changes: muting it on "I'm done".
  final List<http.BaseRequest> pushRuleWrites = [];

  _DiscussionRoomServer(this.path, this.handle);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRoleWrite = request.url.path.contains(
      '/state/${PangeaEventTypes.activityRole}',
    );
    final isPushRule = request.url.path.contains('/pushrules/');
    if (isRoleWrite || isPushRule) {
      (isRoleWrite ? roleWrites : pushRuleWrites).add(request);
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'event_id': r'$seats'}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path != path) return _matrix.send(request);
    final response = handle(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}
