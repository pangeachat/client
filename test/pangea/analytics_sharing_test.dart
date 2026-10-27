import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/analytics_sharing_extension.dart';
import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_handler.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const teacherA = '@teacherA:fakeServer.notExisting';
  const coTeacher = '@coteacher:fakeServer.notExisting';
  const teacherC = '@teacherC:fakeServer.notExisting';
  const courseA = '!courseA:fakeServer.notExisting';
  const courseB = '!courseB:fakeServer.notExisting';
  const courseC = '!courseC:fakeServer.notExisting';
  const analyticsRoomId = '!analytics:fakeServer.notExisting';
  const grantPath =
      '/_synapse/client/pangea/v1/grant_instructor_analytics_access';

  late Client client;
  late FakeMatrixApi api;
  late List<String> kicked;
  late List<Map<String, dynamic>> grants;

  setUpAll(() async {
    // The teacher sets skip the bot by name: BotName.byEnvironment reads
    // GetStorage (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('analytics_sharing');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
  });

  setUp(() async {
    client = await getTestClient();
    api = FakeMatrixApi.currentApi!;
    kicked = [];
    grants = [];
    api.api['POST']!['/client/v3/rooms/!analytics%3AfakeServer.notExisting'
        '/kick'] = (body) {
      kicked.add((jsonDecode(body as String) as Map)['user_id'] as String);
      return {};
    };
    api.api['POST']![grantPath] = (body) {
      grants.add(jsonDecode(body as String) as Map<String, dynamic>);
      return {};
    };
    api.api['GET']!['/client/v3/profile/%40test%3AfakeServer.notExisting'] =
        (_) => {
          PangeaEventTypes.profileAnalytics: {
            'analytics': {
              'de': {'level': 1, 'analytics_room_id': analyticsRoomId},
            },
          },
        };
  });

  tearDown(() async {
    await client.dispose();
  });

  Event state(
    Room room,
    String type,
    Map<String, Object?> content, {
    String stateKey = '',
  }) => Event(
    type: type,
    content: content,
    senderId: userId,
    eventId: '\$$type-$stateKey-${room.id}',
    originServerTs: DateTime.utc(2026, 1, 1),
    stateKey: stateKey,
    room: room,
  );

  Room course(String id, List<String> teachers) {
    final room = Room(id: id, client: client, membership: Membership.join);
    room.setState(
      state(room, EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace}),
    );
    room.setState(
      state(room, EventTypes.RoomPowerLevels, {
        'users': {userId: 0, for (final t in teachers) t: 100},
      }),
    );
    room.setState(
      state(
        room,
        PangeaEventTypes.coursePlan,
        CoursePlanEvent(uuid: 'quest-1', l2: 'de').toJson(),
      ),
    );
    room.setState(
      state(
        room,
        PangeaEventTypes.courseSettings,
        CourseSettingsModel(requireAnalyticsAccess: true).toJson(),
      ),
    );
    return room;
  }

  Room analyticsRoom(List<String> viewers) {
    final room = Room(
      id: analyticsRoomId,
      client: client,
      membership: Membership.join,
    );
    room.setState(
      state(room, EventTypes.RoomCreate, {
        'type': PangeaRoomTypes.analytics,
        ModelKey.langCode: 'de',
      }),
    );
    for (final id in [userId, ...viewers]) {
      room.setState(
        state(room, EventTypes.RoomMember, {
          'membership': 'join',
        }, stateKey: id),
      );
    }
    room.summary = RoomSummary.fromJson({
      'm.joined_member_count': viewers.length + 1,
      'm.invited_member_count': 0,
    });
    return room;
  }

  test('lists the courses one of whose teachers sees the analytics', () async {
    client.rooms = [
      course(courseA, [teacherA, coTeacher]),
      course(courseB, [coTeacher]),
      course(courseC, [teacherC]),
      analyticsRoom([teacherA, coTeacher]),
    ];

    final shared = await client.coursesSharingAnalytics();

    expect(shared.map((r) => r.id), [courseA, courseB]);
  });

  // Leaving stops the sharing (course-analytics-access.instructions.md).
  test('leaving removes the course\'s teachers, but not one who still teaches '
      'another of the learner\'s courses', () async {
    final leaving = course(courseA, [teacherA, coTeacher]);
    client.rooms = [
      leaving,
      course(courseB, [coTeacher]),
      analyticsRoom([teacherA, coTeacher]),
    ];

    await client.removeCourseTeachersFromAnalytics(leaving);

    expect(kicked, [teacherA]);
  });

  test('leaving a course removes its teachers before the leave', () async {
    var left = false;
    api.api['POST']!['/client/v3/rooms/!courseA%3AfakeServer.notExisting'
        '/leave'] = (_) {
      left = true;
      return {};
    };
    final leaving = course(courseA, [teacherA]);
    client.rooms = [
      leaving,
      analyticsRoom([teacherA]),
    ];

    await leaving.leaveSpace();

    expect(kicked, [teacherA]);
    expect(left, isTrue);
  });

  testWidgets(
    'a join that outran sync grants and tells once the course lands',
    (tester) async {
      client.rooms = [];
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      JoinRoomAnalyticsAccessHandler.handleOnceSynced(
        client,
        courseA,
        navigatorContext: () => context,
      );
      await tester.pump();
      expect(grants, isEmpty);

      client.rooms = [
        course(courseA, [teacherA]),
      ];
      client.onSync.add(SyncUpdate(nextBatch: 'landed'));
      for (var i = 0; i < 5 && grants.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
      }

      expect(grants.single['mx_course_id'], courseA);
      expect(
        find.textContaining('can now see your learning progress'),
        findsOneWidget,
      );
      // Let the snackbar time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    },
  );
}
