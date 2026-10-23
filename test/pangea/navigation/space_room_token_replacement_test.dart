import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/space_room_token_extension.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_constants.dart';
import '../get_test_client.dart';

/// #9401 — Synapse's missed-message email links to the room of the unread
/// message, and a course ping is posted in the course space. A room token
/// naming a space is replaced: a ping opens its activity, anything else
/// opens the course.
void main() {
  sqfliteFfiInit();

  const courseId = '!pingcourse:example.com';
  const sessionId = '!pingsession:example.com';
  const activityId = 'activity-9401';
  const pingId = r'$ping:example.com';
  const chatId = r'$chat:example.com';

  late Client client;

  MatrixEvent message(String eventId, Map<String, Object?> extra) =>
      MatrixEvent(
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': 'hi', ...extra},
        senderId: '@teacher:example.com',
        eventId: eventId,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
      );

  Future<void> sync({required bool sessionJoined}) => client.handleSync(
    SyncUpdate(
      nextBatch: 'b1',
      rooms: RoomsUpdate(
        join: {
          courseId: JoinedRoomUpdate(
            state: [
              MatrixEvent(
                type: EventTypes.RoomCreate,
                content: {'type': 'm.space'},
                stateKey: '',
                senderId: '@teacher:example.com',
                eventId: r'$create:example.com',
                originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
              ),
            ],
            timeline: TimelineUpdate(
              events: [
                message(pingId, {
                  CoursePingConstants.coursePingRoomId: sessionId,
                  CoursePingConstants.coursePingActivityId: activityId,
                }),
                message(chatId, {}),
              ],
            ),
          ),
          if (sessionJoined) sessionId: JoinedRoomUpdate(),
        },
      ),
    ),
  );

  Uri emailLink(String? eventId) => Uri.parse(
    WorkspaceNav.openRoomById(Uri.parse('/'), courseId, event: eventId),
  );

  Future<Uri> replacement(String? eventId) async => Uri.parse(
    await client
        .getRoomById(courseId)!
        .spaceTokenReplacement(emailLink(eventId), eventId: eventId),
  );

  void expectCourse(Uri uri) {
    expect(activeSpaceIdFor(uri), courseId);
    final left = parseOpenPanels(uri).left;
    expect(left.map((t) => t.type), [PanelTypesEnum.course]);
  }

  setUp(() async {
    client = await getTestClient();
    FakeMatrixApi.client = client;
  });

  test('a ping opens the joined session', () async {
    await sync(sessionJoined: true);
    final left = parseOpenPanels(await replacement(pingId)).left;
    expect(left, hasLength(1));
    expect(left.single.type, PanelTypesEnum.room);
    final param = left.single.param as RoomTokenParam;
    expect(fullRoomId(param.id), sessionId);
  });

  test('a ping opens the activity in its course before joining', () async {
    await sync(sessionJoined: false);
    final uri = await replacement(pingId);
    expect(activeSpaceIdFor(uri), courseId);
    final left = parseOpenPanels(uri).left;
    expect(left, hasLength(1));
    final param = (left.single as ActivityPanelToken).param!;
    expect(param.activityId, activityId);
    expect(param.roomId, sessionId);
  });

  test('a message that is not a ping opens the course', () async {
    await sync(sessionJoined: false);
    expectCourse(await replacement(chatId));
  });

  test('a link without an event opens the course', () async {
    await sync(sessionJoined: false);
    expectCourse(await replacement(null));
  });

  test('an event the server cannot find opens the course', () async {
    await sync(sessionJoined: false);
    expectCourse(await replacement(r'$missing:example.com'));
  });
}
