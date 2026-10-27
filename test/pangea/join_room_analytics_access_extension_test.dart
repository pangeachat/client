import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/analytics_access_notice_dialog.dart';
import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/l10n/l10n.dart';
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

  Room courseRoom({bool requireAnalyticsAccess = true, int powerLevel = 0}) {
    final room = Room(
      id: courseRoomId,
      client: client,
      membership: Membership.join,
    );
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: {
          'users': {userId: powerLevel},
        },
        senderId: userId,
        eventId: '\$powerLevels',
        originServerTs: DateTime.utc(2026, 1, 1),
        stateKey: '',
        room: room,
      ),
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
        content: CourseSettingsModel(
          requireAnalyticsAccess: requireAnalyticsAccess,
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
    testWidgets('admin claim ignores a stale learner notice response', (
      tester,
    ) async {
      final room = courseRoom(powerLevel: 100);
      client.rooms = [room];
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      );
      final before = FakeMatrixApi.calledEndpoints.toString();
      final result = await JoinRoomAnalyticsConsentHandler(
        const JoinResponse(roomId: courseRoomId, shouldShowNotice: true),
        room,
      ).handle(context);

      expect(result, courseRoomId);
      expect(FakeMatrixApi.calledEndpoints.toString(), before);
      expect(grants, isEmpty);
    });

    test('course admin skips the learner notice and analytics grant', () async {
      profileWithAnalyticsRoom(analyticsRoomId);
      final room = courseRoom(powerLevel: 100);
      client.rooms = [room];

      expect(room.shouldShowAnalyticsAccessNotice, false);
      await client.grantInstructorsAnalyticsAccess(courseRoomId);
      await client.grantAnalyticsAccessByAnalyticsRoom(analyticsRoomId, 'de');

      expect(grants, isEmpty);
    });

    test('ordinary learner still sees the required analytics notice', () {
      expect(courseRoom().shouldShowAnalyticsAccessNotice, true);
    });

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

    test(
      'does not grant on a course that does not require analytics access',
      () async {
        // CLIENT-EFF (#9270): every course join runs this, and on an optional
        // course the server refuses the grant with a 403. Access there is
        // asked for by an instructor and allowed by the student instead.
        profileWithAnalyticsRoom(analyticsRoomId);
        client.rooms = [
          courseRoom(requireAnalyticsAccess: false),
          analyticsRoom(analyticsRoomId),
        ];

        await client.grantInstructorsAnalyticsAccess(courseRoomId);

        expect(grants, isEmpty);
      },
    );
  });

  group('JoinRoomAnalyticsConsentHandler', () {
    // CLIENT-EFF: a class-link join and a second caller each ran the handler
    // for the same course, stacking two notices. The learner chose Go back on
    // one (leaving the course) and Share and join on the other, which granted
    // for a course they had just left.
    testWidgets('concurrent calls for one course share a single notice', (
      tester,
    ) async {
      profileWithAnalyticsRoom(analyticsRoomId);
      api.api['PUT']!['/client/v3/user/${Uri.encodeComponent(userId)}'
          '/account_data/${PangeaEventTypes.accessNoticeShown}'] = (_) =>
          {};
      var leaves = 0;
      api.api['POST']!['/client/v3/rooms/${Uri.encodeComponent(courseRoomId)}'
          '/leave'] = (_) {
        leaves++;
        return {};
      };
      final room = courseRoom();
      client.rooms = [room];
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      const joinResp = JoinResponse(
        roomId: courseRoomId,
        shouldShowNotice: true,
      );
      final results = <String?>[];
      for (var i = 0; i < 2; i++) {
        JoinRoomAnalyticsConsentHandler(
          joinResp,
          room,
        ).handle(context).then(results.add);
      }
      // The notice and the leave wait on real I/O; let it land, then build.
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
      }

      await settle();
      expect(find.byType(AnalyticsAccessNoticeDialog), findsOneWidget);

      await tester.tap(find.text(L10n.of(context).goBack));
      for (var i = 0; i < 5 && results.length < 2; i++) {
        await settle();
      }

      expect(results, [null, null]);
      expect(leaves, 1);
      expect(grants, isEmpty);
    });
  });
}
