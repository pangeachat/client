import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/bot/bot_event_extension.dart';
import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/bot_notice_widget.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'get_test_client.dart';
import 'sentry_capture_harness.dart';

/// #9478 — a notice opens the place it names, from its push and from its Open
/// button in the bot DM, and the bot DM shows it as the bot's message
/// (notices.instructions.md). An app path is followed only from a notice the
/// bot sent into the bot DM: some paths do more than open a page, and any
/// Matrix user can put the key into an event they send.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const botId = '@bot:example.com';
  const strangerId = '@stranger:example.com';
  const botDmId = '!botdm:example.com';
  // Marked a bot DM by its bot settings alone, which any member allowed to
  // change room settings can write.
  const fakeBotDmId = '!fakebotdm:example.com';
  const groupId = '!group:example.com';
  const courseId = '!course:example.com';
  const joinedSessionId = '!joinedsession:example.com';
  const leftSessionId = '!leftsession:example.com';
  const activityId = '0b7f5a1e-3c2d-4e5f-8a9b-1c2d3e4f5a6b';
  const pathKey = 'content_${BotEventExtension.noticeDestinationPathKey}';

  late Client client;
  late SentryCaptureHarness sentry;

  setUpAll(() async {
    // BotName.byEnvironment reads GetStorage and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('notice_destination');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {'BOT_NAME': botId, 'SYNAPSE_URL': 'https://example.com'},
    );
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    // The bot's avatar reads the image cache, which opens a database.
    databaseFactory = databaseFactoryFfi;
  });

  MatrixEvent createEvent({String? type}) => MatrixEvent(
    type: EventTypes.RoomCreate,
    content: {'type': ?type},
    stateKey: '',
    senderId: strangerId,
    eventId: '\$create${type ?? ''}',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  );

  setUp(() async {
    sentry = SentryCaptureHarness();
    await sentry.init();
    client = await getTestClient(
      importantStateEvents: {PangeaEventTypes.botOptions},
    );
    FakeMatrixApi.client = client;
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'b1',
        accountData: [
          BasicEvent(
            type: 'm.direct',
            content: {
              botId: [botDmId],
            },
          ),
        ],
        rooms: RoomsUpdate(
          join: {
            botDmId: JoinedRoomUpdate(state: [createEvent()]),
            fakeBotDmId: JoinedRoomUpdate(
              state: [
                createEvent(),
                MatrixEvent(
                  type: PangeaEventTypes.botOptions,
                  content: {'mode': 'direct_chat'},
                  stateKey: '',
                  senderId: strangerId,
                  eventId: '\$botoptions',
                  originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
                ),
              ],
            ),
            groupId: JoinedRoomUpdate(state: [createEvent()]),
            courseId: JoinedRoomUpdate(state: [createEvent(type: 'm.space')]),
            joinedSessionId: JoinedRoomUpdate(state: [createEvent()]),
          },
        ),
      ),
    );
  });

  tearDown(() async {
    await sentry.close();
    await client.dispose();
  });

  Event notice(
    String roomId, {
    String senderId = botId,
    Map<String, Object?> content = const {},
  }) => Event(
    type: PangeaEventTypes.botNotice,
    content: {'body': 'Ready for your next activity?', ...content},
    senderId: senderId,
    eventId: '\$notice',
    originServerTs: DateTime.now(),
    room: client.getRoomById(roomId)!,
  );

  Future<Uri> tap(
    WidgetTester tester,
    String roomId,
    Map<String, dynamic> notification,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      redirect: (_, state) => LegacyRedirects.handle(state.uri),
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => NotificationTapUtil.handleNotificationTap(
        client: client,
        roomId: roomId,
        notification: {'event_id': '\$notice', ...notification},
        router: router,
      ),
    );
    await tester.pumpAndSettle();
    return router.routerDelegate.currentConfiguration.uri;
  }

  /// The report a refused path left, once Sentry's async pipeline delivers it.
  Future<String?> lastReport(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    return sentry.events.lastOrNull?.throwable?.toString();
  }

  String? openedRoomId(Uri uri) {
    final left = parseOpenPanels(uri).left;
    return left.length == 1 && left.single is RoomPanelToken
        ? (left.single as RoomPanelToken).param!.id
        : null;
  }

  group('push tap', () {
    testWidgets('follows a path from the bot in its DM, folding short links', (
      tester,
    ) async {
      final uri = await tap(tester, botDmId, {
        'sender': botId,
        pathKey: '/$activityId',
      });
      final left = parseOpenPanels(uri).left;
      expect(left.single.type, PanelTypesEnum.activity);
      expect((left.single as ActivityPanelToken).param!.activityId, activityId);
    });

    testWidgets('follows a token path from the bot in its DM', (tester) async {
      final uri = await tap(tester, botDmId, {
        'sender': botId,
        pathKey: '/?right=settingspage:subscription',
      });
      expect(uri.queryParameters['right'], 'settingspage:subscription');
    });

    testWidgets('ignores a path from anyone but the bot, in a room whose '
        'settings call it a bot DM', (tester) async {
      final uri = await tap(tester, fakeBotDmId, {
        'sender': strangerId,
        pathKey: '/$activityId',
      });
      expect(openedRoomId(uri), fakeBotDmId);
      expect(await lastReport(tester), contains('not sent by the bot'));
    });

    testWidgets('ignores a path from the bot outside its DM', (tester) async {
      final uri = await tap(tester, groupId, {
        'sender': botId,
        pathKey: '/$activityId',
      });
      expect(openedRoomId(uri), groupId);
      expect(await lastReport(tester), contains('not sent by the bot'));
    });

    testWidgets('ignores a path that leaves the app', (tester) async {
      final uri = await tap(tester, botDmId, {
        'sender': botId,
        pathKey: '//evil.example.com/$activityId',
      });
      expect(openedRoomId(uri), botDmId);
      expect(await lastReport(tester), contains('not an app path'));
    });

    testWidgets('the session keys win over a path', (tester) async {
      final uri = await tap(tester, botDmId, {
        'sender': botId,
        pathKey: '/?right=settingspage:subscription',
        'content_pangea.activity.id': activityId,
        'content_pangea.activity.session_room_id': joinedSessionId,
      });
      expect(openedRoomId(uri), joinedSessionId);
      expect(uri.queryParameters['right'], isNull);
    });

    testWidgets('a notice\'s session the learner left opens its activity with '
        'no course', (tester) async {
      final uri = await tap(tester, botDmId, {
        'sender': botId,
        'content_pangea.activity.id': activityId,
        'content_pangea.activity.session_room_id': leftSessionId,
      });
      final param =
          (parseOpenPanels(uri).left.single as ActivityPanelToken).param!;
      expect(param.activityId, activityId);
      expect(param.roomId, leftSessionId);
      expect(activeSpaceIdFor(uri), isNull);
    });

    testWidgets('a course ping still opens its activity in its course', (
      tester,
    ) async {
      final uri = await tap(tester, courseId, {
        'sender': strangerId,
        'content_pangea.activity.id': activityId,
        'content_pangea.activity.session_room_id': leftSessionId,
      });
      expect(activeSpaceIdFor(uri), courseId);
    });
  });

  group('the notice in the bot DM', () {
    test('shows a notice the bot sent into its DM', () {
      expect(notice(botDmId).isShownBotNotice, isTrue);
      expect([notice(botDmId)].filterByVisibleInGui(), hasLength(1));
    });

    test('hides suggest_topic, which pangea-bot posts as its own message', () {
      final topic = notice(
        botDmId,
        content: {'check_in_type': 'suggest_topic'},
      );
      expect(topic.isShownBotNotice, isFalse);
      expect([topic].filterByVisibleInGui(), isEmpty);
    });

    test('hides a notice from anyone else, from another room, or with no '
        'text', () {
      expect(
        notice(fakeBotDmId, senderId: strangerId).isShownBotNotice,
        isFalse,
      );
      expect(notice(groupId).isShownBotNotice, isFalse);
      expect(notice(botDmId, content: {'body': ''}).isShownBotNotice, isFalse);
      expect(
        [
          notice(groupId),
          notice(fakeBotDmId, senderId: strangerId),
        ].filterByVisibleInGui(),
        isEmpty,
      );
    });

    test('has a destination when it names a session or an app path', () {
      expect(notice(botDmId).hasNoticeDestination, isFalse);
      expect(
        notice(
          botDmId,
          content: {
            'pangea.activity.id': activityId,
            'pangea.activity.session_room_id': joinedSessionId,
          },
        ).hasNoticeDestination,
        isTrue,
      );
      // The tap handler skips empty session keys, so they name no place.
      expect(
        notice(
          botDmId,
          content: {
            'pangea.activity.id': '',
            'pangea.activity.session_room_id': joinedSessionId,
          },
        ).hasNoticeDestination,
        isFalse,
      );
      expect(
        notice(
          botDmId,
          content: {BotEventExtension.noticeDestinationPathKey: '/$activityId'},
        ).hasNoticeDestination,
        isTrue,
      );
      for (final outside in [
        'https://evil.example.com/x',
        '//evil.example.com/x',
        'settings',
      ]) {
        expect(
          notice(
            botDmId,
            content: {BotEventExtension.noticeDestinationPathKey: outside},
          ).hasNoticeDestination,
          isFalse,
          reason: outside,
        );
      }
    });

    test('its Open button sends the same data its push would carry', () {
      final data = NotificationTapUtil.notificationDataFor(
        notice(
          botDmId,
          content: {
            'check_in_type': 'try_activity',
            BotEventExtension.noticeDestinationPathKey: '/$activityId',
          },
        ),
      );
      expect(data['event_id'], '\$notice');
      expect(data['room_id'], botDmId);
      expect(data['sender'], botId);
      expect(data['content_check_in_type'], 'try_activity');
      expect(data[pathKey], '/$activityId');
    });

    testWidgets('shows its text, with Open only when it names a place', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        redirect: (_, state) => LegacyRedirects.handle(state.uri),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Column(
                children: [
                  BotNoticeWidget(notice(botDmId)),
                  BotNoticeWidget(
                    notice(
                      botDmId,
                      content: {
                        BotEventExtension.noticeDestinationPathKey:
                            '/?right=settingspage:subscription',
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      );
      // The bot's avatar animates, so the tree never settles.
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Ready for your next activity?'), findsNWidgets(2));
      expect(find.text('Open'), findsOneWidget);

      await tester.tap(find.text('Open'));
      // The tap waits on the client's loading futures, which need real time.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['right'],
        'settingspage:subscription',
      );
    });

    testWidgets('its Open button records the open and goes to the place', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        redirect: (_, state) => LegacyRedirects.handle(state.uri),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      FakeMatrixApi.calledEndpoints.clear();

      await tester.runAsync(
        () => NotificationTapUtil.openNotice(
          notice(
            botDmId,
            content: {
              'check_in_type': 'try_activity',
              BotEventExtension.noticeDestinationPathKey: '/$activityId',
            },
          ),
          router,
        ),
      );
      await tester.pumpAndSettle();

      final uri = router.routerDelegate.currentConfiguration.uri;
      expect(parseOpenPanels(uri).left.single.type, PanelTypesEnum.activity);
      // The opened event is sent without awaiting, as on a push tap.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      expect(
        FakeMatrixApi.calledEndpoints.keys.where(
          (endpoint) => endpoint.contains(
            '/send/${PangeaEventTypes.botNotificationOpened}/',
          ),
        ),
        hasLength(1),
      );
    });
  });
}
