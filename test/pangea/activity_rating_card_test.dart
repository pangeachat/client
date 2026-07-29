import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_rating_store.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_rating_card.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';

/// Visibility contract of the post-play rating prompt (#7194): shows only for
/// a finished own role on an unrated (activity, pinned version); submit is
/// disabled until a thumb is picked; the X dismisses for the current view.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const roomId = '!1234:fakeServer.notExisting';
  const activityId = 'rating-test-activity';

  setUpAll(() async {
    // GetStorage needs path_provider; stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('rating_card_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async {
    await GetStorage.init(ActivityRatingStore.storageKey);
    await GetStorage(ActivityRatingStore.storageKey).erase();
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Room sessionRoom({required bool finished}) {
    final room = Room(id: roomId, client: client);
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': '${PangeaRoomTypes.activitySession}:$activityId'},
        senderId: userId,
        eventId: '\$create',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: room,
      ),
    );
    final role = ActivityRoleModel(
      id: 'role1',
      userId: userId,
      role: 'debater',
      finishedAt: finished ? DateTime.utc(2026, 1, 1, 13) : null,
    );
    room.setState(
      Event(
        type: PangeaEventTypes.activityRole,
        content: ActivityRolesModel({role.id: role}).toJson(),
        senderId: userId,
        eventId: '\$role',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: room,
      ),
    );
    return room;
  }

  Future<void> pumpCard(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        // The test host can't load Material 3's ink-sparkle shader.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: ActivityRatingCard(room: room)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hidden while the own role is unfinished', (tester) async {
    await pumpCard(tester, sessionRoom(finished: false));
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
  });

  testWidgets('shows for a finished, unrated session', (tester) async {
    await pumpCard(tester, sessionRoom(finished: true));
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('submit is disabled until a thumb is picked', (tester) async {
    await pumpCard(tester, sessionRoom(finished: true));

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await tester.pumpAndSettle();

    final enabled = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(enabled.onPressed, isNotNull);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
  });

  testWidgets('X dismisses the card for this view', (tester) async {
    await pumpCard(tester, sessionRoom(finished: true));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
  });

  testWidgets('hidden when this (activity, version) was already rated', (
    tester,
  ) async {
    await ActivityRatingStore.markRated(activityId, null);
    await pumpCard(tester, sessionRoom(finished: true));
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
  });
}
