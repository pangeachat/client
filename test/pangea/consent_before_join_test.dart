import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/analytics_access/analytics_access_notice_dialog.dart';
import 'package:fluffychat/features/analytics_access/consent_before_join.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const teacherId = '@teacher:fakeServer.notExisting';
  const courseRoomId = '!course:fakeServer.notExisting';
  const analyticsRoomId = '!analytics:fakeServer.notExisting';
  const code = 'abc1234';
  const previewPath = '/_synapse/client/pangea/v1/preview_with_code';
  const knockPath = '/_synapse/client/pangea/v1/knock_with_code';
  const accountDataPath =
      '/client/v3/user/%40test%3AfakeServer.notExisting'
      '/account_data/${PangeaEventTypes.accessNoticeShown}';

  late Client client;
  late FakeMatrixApi api;
  late List<Object?> noticeWrites;
  late int knocks;

  setUpAll(() async {
    // The teacher list skips the bot by name (BotName.byEnvironment reads
    // GetStorage and dotenv), and the code join stores the code it was given.
    final tempDir = await Directory.systemTemp.createTemp('consent_before');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    await GetStorage.init('class_storage');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
  });

  setUp(() async {
    client = await getTestClient();
    api = FakeMatrixApi.currentApi!;
    noticeWrites = [];
    knocks = 0;
    api.api['PUT']![accountDataPath] = (body) {
      noticeWrites.add(jsonDecode(body as String));
      return {};
    };
    api.api['POST']![knockPath] = (_) {
      knocks++;
      return {
        'rooms': <String>[],
        'already_joined': <String>[],
        'banned': <String>[],
      };
    };
  });

  tearDown(() async {
    await client.dispose();
  });

  Map<String, dynamic> codePreviewRoom({
    bool? requiresSharing = true,
    bool opensAsAdmin = false,
  }) => {
    'room_id': courseRoomId,
    'name': 'Spanish 101',
    'admins': [
      {'user_id': teacherId, 'avatar_url': null},
    ],
    'opens_as_admin': opensAsAdmin,
    'state_events': {
      PangeaEventTypes.coursePlan: {
        'default': {
          'content': {'uuid': 'quest-1', 'l2': 'de'},
        },
      },
      if (requiresSharing != null)
        PangeaEventTypes.courseSettings: {
          'default': {
            'content': {'require_analytics_access': requiresSharing},
          },
        },
    },
  };

  CourseJoinPreview preview({
    bool? requiresSharing = true,
    bool opensAsAdmin = false,
  }) => CourseJoinPreview.fromCodePreview(
    codePreviewRoom(
      requiresSharing: requiresSharing,
      opensAsAdmin: opensAsAdmin,
    ),
  );

  Future<BuildContext> pumpHost(WidgetTester tester) async {
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
    return context;
  }

  // The question and the answer's write wait on real I/O; let it land, then
  // build.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  group('CourseJoinPreview', () {
    test('reads the code preview', () {
      final p = preview();
      expect(p.roomId, courseRoomId);
      expect(p.requiresSharing, isTrue);
      expect(p.opensAsTeacher, isFalse);
      expect(p.languageCode, 'de');
      expect(p.teacherIds, {teacherId});
    });

    test(
      'an old server without the setting leaves the requirement unknown',
      () {
        expect(preview(requiresSharing: null).requiresSharing, isNull);
      },
    );

    test('reads room_preview, where power levels name the teachers', () {
      final summary = RoomSummariesResponse.fromJson({
        'rooms': {
          courseRoomId: {
            PangeaEventTypes.courseSettings: {
              'default': {
                'content': {'require_analytics_access': true},
              },
            },
            PangeaEventTypes.coursePlan: {
              'default': {
                'content': {'uuid': 'quest-1', 'l2': 'de'},
              },
            },
            EventTypes.RoomPowerLevels: {
              'default': {
                'content': {
                  'users': {teacherId: 100, userId: 0},
                },
              },
            },
          },
        },
      }, l1Code: null).summaries[courseRoomId]!;

      final p = CourseJoinPreview.fromRoomSummary(
        courseRoomId,
        summary,
        userId,
      );
      expect(p.requiresSharing, isTrue);
      expect(p.opensAsTeacher, isFalse);
      expect(p.languageCode, 'de');
      expect(p.teacherIds, {teacherId});
      expect(
        CourseJoinPreview.fromRoomSummary(
          courseRoomId,
          summary,
          teacherId,
        ).opensAsTeacher,
        isTrue,
      );
    });
  });

  group('AnalyticsConsentBeforeJoin.ask', () {
    Future<bool?> askAndAnswer(
      WidgetTester tester,
      CourseJoinPreview p, {
      String? tap,
    }) async {
      final context = await pumpHost(tester);
      bool? proceed;
      AnalyticsConsentBeforeJoin.ask(
        client,
        p,
        navigatorContext: () => context,
      ).then((value) => proceed = value);
      await settle(tester);
      if (tap != null) {
        expect(find.byType(AnalyticsAccessNoticeDialog), findsOneWidget);
        await tester.tap(find.text(tap));
        for (var i = 0; i < 5 && proceed == null; i++) {
          await settle(tester);
        }
      }
      return proceed;
    }

    testWidgets('Go back joins nothing and records nothing', (tester) async {
      final proceed = await askAndAnswer(tester, preview(), tap: 'Go back');
      expect(proceed, isFalse);
      expect(noticeWrites, isEmpty);
    });

    testWidgets('Share and join records the answer before the join', (
      tester,
    ) async {
      final proceed = await askAndAnswer(
        tester,
        preview(),
        tap: 'Share and join',
      );
      expect(proceed, isTrue);
      expect(noticeWrites, [
        {
          'notices_accepted': {courseRoomId: true},
        },
      ]);
    });

    testWidgets('a teacher is not asked', (tester) async {
      final proceed = await askAndAnswer(tester, preview(opensAsAdmin: true));
      expect(find.byType(AnalyticsAccessNoticeDialog), findsNothing);
      expect(proceed, isTrue);
    });

    testWidgets('an old server leaves the question to follow the join', (
      tester,
    ) async {
      final proceed = await askAndAnswer(
        tester,
        preview(requiresSharing: null),
      );
      expect(find.byType(AnalyticsAccessNoticeDialog), findsNothing);
      expect(proceed, isTrue);
      expect(noticeWrites, isEmpty);
    });

    testWidgets('a learner whose teacher already sees their analytics is '
        'not asked', (tester) async {
      final analytics = Room(
        id: analyticsRoomId,
        client: client,
        membership: Membership.join,
      );
      analytics.setState(
        Event(
          type: EventTypes.RoomCreate,
          content: {'type': PangeaRoomTypes.analytics, ModelKey.langCode: 'de'},
          senderId: userId,
          eventId: '\$create',
          originServerTs: DateTime.utc(2026, 1, 1),
          stateKey: '',
          room: analytics,
        ),
      );
      for (final id in [userId, teacherId]) {
        analytics.setState(
          Event(
            type: EventTypes.RoomMember,
            content: {'membership': 'join'},
            senderId: id,
            eventId: '\$member-$id',
            originServerTs: DateTime.utc(2026, 1, 1),
            stateKey: id,
            room: analytics,
          ),
        );
      }
      analytics.summary = RoomSummary.fromJson({
        'm.joined_member_count': 2,
        'm.invited_member_count': 0,
      });
      client.rooms = [analytics];

      final proceed = await askAndAnswer(tester, preview());
      expect(find.byType(AnalyticsAccessNoticeDialog), findsNothing);
      expect(proceed, isTrue);
      expect(noticeWrites, [
        {
          'notices_accepted': {courseRoomId: true},
        },
      ]);
    });
  });

  // The 2026-10-26 class: a student who went back after a code join was
  // removed from their course. Asked before the knock, going back never
  // reaches the server.
  testWidgets('a code join the student goes back from never knocks', (
    tester,
  ) async {
    api.api['POST']![previewPath] = (_) => {
      'rooms': [codePreviewRoom()],
    };
    final context = await pumpHost(tester);

    Object? error;
    SpaceCodeController.joinSpaceWithCode(
      code,
      client: client,
      context: context,
      showLoading: false,
    ).then((result) => error = result.asError?.error);
    await settle(tester);
    await tester.tap(find.text('Go back'));
    for (var i = 0; i < 5 && error == null; i++) {
      await settle(tester);
    }

    expect(error, isA<AnalyticsConsentDeclined>());
    expect(knocks, 0);
  });
}
