import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const courseRoomId = '!course:fakeServer.notExisting';
  const analyticsRoomId = '!analytics:fakeServer.notExisting';
  const grantPath =
      '/_synapse/client/pangea/v1/grant_instructor_analytics_access';

  late Client client;
  late FakeMatrixApi api;
  late List<Map<String, dynamic>> grants;

  setUp(() async {
    client = await getTestClient();
    api = FakeMatrixApi.currentApi!;
    grants = [];

    api.api['POST']![grantPath] = (body) {
      grants.add(jsonDecode(body as String) as Map<String, dynamic>);
      return {};
    };
  });

  tearDown(() async {
    await client.dispose();
  });

  Room courseRoom() {
    final room = Room(
      id: courseRoomId,
      client: client,
      membership: Membership.join,
    );
    room.setState(
      Event(
        type: PangeaEventTypes.coursePlan,
        content: CoursePlanEvent(uuid: 'quest-1', l2: 'de').toJson(),
        senderId: userId,
        eventId: '\$coursePlan',
        originServerTs: DateTime.utc(2026, 1, 1),
        stateKey: '',
        room: room,
      ),
    );
    room.setState(
      Event(
        type: PangeaEventTypes.courseSettings,
        content: const CourseSettingsModel(
          requireAnalyticsAccess: true,
        ).toJson(),
        senderId: userId,
        eventId: '\$courseSettings',
        originServerTs: DateTime.utc(2026, 1, 1),
        stateKey: '',
        room: room,
      ),
    );
    return room;
  }

  Room analyticsRoom(String id) {
    final room = Room(id: id, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': PangeaRoomTypes.analytics, ModelKey.langCode: 'de'},
        senderId: userId,
        eventId: '\$create-$id',
        originServerTs: DateTime.utc(2026, 1, 1),
        stateKey: '',
        room: room,
      ),
    );
    return room;
  }

  void profileWithAnalyticsRoom(String? roomId) {
    api.api['GET']!['/client/v3/profile/%40test%3AfakeServer.notExisting'] =
        (_) => {
          PangeaEventTypes.profileAnalytics: {
            'analytics': {
              'de': {
                'level': 1,
                ...roomId == null ? const {} : {'analytics_room_id': roomId},
              },
            },
          },
        };
  }

  List<String> createRoomCalls() => FakeMatrixApi.calledEndpoints.keys
      .where((path) => path.contains('/createRoom'))
      .toList();

  group('grantInstructorsAnalyticsAccess', () {
    test(
      'grants using profile analytics_room_id without a local analytics room',
      () async {
        profileWithAnalyticsRoom(analyticsRoomId);
        client.rooms = [courseRoom()];

        await client.grantInstructorsAnalyticsAccess(courseRoomId);

        expect(grants, [
          {
            'mx_course_id': courseRoomId,
            'mx_analytics_room_id': analyticsRoomId,
          },
        ]);
        expect(createRoomCalls(), isEmpty);
      },
    );

    test(
      'falls back to the local canonical analytics room before the call',
      () async {
        profileWithAnalyticsRoom(null);
        client.rooms = [courseRoom(), analyticsRoom(analyticsRoomId)];

        await client.grantInstructorsAnalyticsAccess(courseRoomId);

        expect(grants.single['mx_analytics_room_id'], analyticsRoomId);
        expect(createRoomCalls(), isEmpty);
      },
    );

    test('prefers the profile room id over the local canonical room', () async {
      // The profile is authoritative and is the SAME source the teacher
      // dashboard reads, so it must win over any local room.
      profileWithAnalyticsRoom(analyticsRoomId);
      client.rooms = [
        courseRoom(),
        analyticsRoom('!stale:fakeServer.notExisting'),
      ];

      await client.grantInstructorsAnalyticsAccess(courseRoomId);

      expect(grants.single['mx_analytics_room_id'], analyticsRoomId);
      expect(createRoomCalls(), isEmpty);
    });

    test(
      'does not grant or create a room when neither profile nor local has one',
      () async {
        profileWithAnalyticsRoom(null);
        client.rooms = [courseRoom()];

        await client.grantInstructorsAnalyticsAccess(courseRoomId);

        expect(grants, isEmpty);
        expect(createRoomCalls(), isEmpty);
      },
    );
  });
}
