import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'get_test_client.dart';

/// #9422 — tapping the notification for an invite to a course or a DM the
/// learner isn't in yet asks them to accept or decline, with the prompt the app
/// already uses for that kind of room, instead of dropping them on the bare
/// world map. Accepting opens the room; declining leaves them where they were.
void main() {
  sqfliteFfiInit();

  // FakeMatrixApi answers join and leave for these two room ids.
  const dmId = '!localpart:example.com';
  const courseId = '!1234:fakeServer.notExisting';
  const inviterId = '@friend:example.com';
  const userId = '@test:fakeServer.notExisting';

  late Client client;
  late L10n l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The inviter's display name reads the bot name from dotenv, and the
    // course prompt reads the join-code cache from GetStorage.
    final tempDir = await Directory.systemTemp.createTemp('invite_prompt');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() async {
    client = await getTestClient();
    FakeMatrixApi.client = client;
    FakeMatrixApi.calledEndpoints.clear();
  });

  StrippedStateEvent inviteFor(String roomId) => StrippedStateEvent(
    type: EventTypes.RoomMember,
    content: {'membership': 'invite', 'is_direct': roomId == dmId},
    stateKey: userId,
    senderId: inviterId,
  );

  Future<void> seedInvite(WidgetTester tester, String roomId) =>
      tester.runAsync(
        () => client.handleSync(
          SyncUpdate(
            nextBatch: 'invite',
            rooms: RoomsUpdate(
              invite: {
                roomId: InvitedRoomUpdate(
                  inviteState: [
                    if (roomId == courseId)
                      StrippedStateEvent(
                        type: EventTypes.RoomCreate,
                        content: {'type': RoomCreationTypes.mSpace},
                        stateKey: '',
                        senderId: inviterId,
                      ),
                    inviteFor(roomId),
                  ],
                ),
              },
            ),
          ),
        ),
      );

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  /// The tap's SDK reads and the fake API answer on the real clock, the
  /// dialogs on the fake one, so alternate the two until both have settled.
  Future<void> settle(WidgetTester tester, {bool spinnerOpen = false}) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    // A loading spinner never settles.
    if (!spinnerOpen) await tester.pumpAndSettle();
  }

  Future<void> tapNotification(GoRouter router, String roomId) =>
      NotificationTapUtil.handleNotificationTap(
        client: client,
        roomId: roomId,
        notification: {'type': EventTypes.RoomMember},
        router: router,
      );

  bool called(String roomId, String action) => FakeMatrixApi.calledEndpoints
      .containsKey('/client/v3/rooms/${Uri.encodeComponent(roomId)}/$action');

  testWidgets('a course invite asks once, and declining stays put', (
    tester,
  ) async {
    await seedInvite(tester, courseId);
    final router = await pumpApp(tester);

    // Twice: the chat list's invite listener can prompt for the same invite
    // the tap is waiting on.
    final taps = Future.wait([
      tapNotification(router, courseId),
      tapNotification(router, courseId),
    ]);
    await settle(tester);

    expect(find.text(l10n.youreInvited), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');

    await tester.tap(find.text(l10n.decline));
    await settle(tester);
    await taps;

    expect(find.text(l10n.youreInvited), findsNothing);
    expect(called(courseId, 'leave'), isTrue);
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
  });

  testWidgets('a DM invite asks, and declining stays put', (tester) async {
    await seedInvite(tester, dmId);
    final router = await pumpApp(tester);

    final tap = tapNotification(router, dmId);
    await settle(tester);

    expect(find.text(l10n.accept), findsOneWidget);
    expect(find.text(l10n.block), findsOneWidget);

    await tester.tap(find.text(l10n.decline));
    await settle(tester);
    await tap;

    expect(find.text(l10n.accept), findsNothing);
    expect(called(dmId, 'leave'), isTrue);
    expect(called(dmId, 'join'), isFalse);
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
  });

  testWidgets('accepting a DM invite joins it and opens the DM', (
    tester,
  ) async {
    await seedInvite(tester, dmId);
    final router = await pumpApp(tester);

    final tap = tapNotification(router, dmId);
    await settle(tester);

    await tester.tap(find.text(l10n.accept));
    await settle(tester, spinnerOpen: true);
    expect(called(dmId, 'join'), isTrue);

    // The join waits for the sync that brings the room back joined, then for
    // that sync to finish processing.
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'joined',
          rooms: RoomsUpdate(join: {dmId: JoinedRoomUpdate()}),
        ),
      ),
    );
    await settle(tester, spinnerOpen: true);
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    await settle(tester);
    await tap;

    final left = parseOpenPanels(
      router.routerDelegate.currentConfiguration.uri,
    ).left;
    expect(left.map((t) => t.type), contains(PanelTypesEnum.room));
  });

  testWidgets('blocking the inviter opens their ignore-list entry', (
    tester,
  ) async {
    await seedInvite(tester, dmId);
    final router = await pumpApp(tester);

    final tap = tapNotification(router, dmId);
    await settle(tester);

    await tester.tap(find.text(l10n.block));
    await settle(tester);
    await tap;

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      contains(Uri.encodeComponent('ignorelist/$inviterId')),
    );
    expect(called(dmId, 'join'), isFalse);
  });
}
