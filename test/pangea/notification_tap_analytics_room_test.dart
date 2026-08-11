import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';

/// Regression coverage for #8268 — tapping a notification for an analytics
/// room must never open it as a chat. The instructor is genuinely JOINED to
/// student analytics rooms (auto-join / auto-grant), so the invite branch
/// never catches this; the tap handler has to refuse the room itself and fall
/// back to the joined parent course, or the world map when there is none.
void main() {
  sqfliteFfiInit();

  // sqflite's ':memory:' database is shared process-wide, so rooms outlive a
  // client (see chat_context_mark_read_test.dart). Distinct ids per test keep
  // one test's parent course from leaking into the next.
  const analyticsRoomId = '!analytics:example.com';
  const orphanAnalyticsRoomId = '!analytics2:example.com';
  const courseId = '!course:example.com';
  const normalRoomId = '!normal:example.com';

  late Client client;

  setUp(() async {
    client = await getTestClient();
    FakeMatrixApi.client = client;
  });

  var eventCounter = 0;
  MatrixEvent stateEvent({
    required String type,
    required Map<String, Object?> content,
    String stateKey = '',
  }) => MatrixEvent(
    type: type,
    content: content,
    stateKey: stateKey,
    senderId: '@teacher:example.com',
    eventId: '\$state${eventCounter++}:example.com',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  );

  JoinedRoomUpdate roomUpdate({String? type}) => JoinedRoomUpdate(
    state: [
      stateEvent(type: EventTypes.RoomCreate, content: {'type': ?type}),
    ],
  );

  /// Pump a bare router at `/`, run the tap handler for [roomId], and return
  /// the location it navigated to.
  Future<Uri> tapNotification(WidgetTester tester, String roomId) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => NotificationTapUtil.handleNotificationTap(
        client: client,
        roomId: roomId,
        notification: null,
        router: router,
      ),
    );
    await tester.pumpAndSettle();
    return router.routerDelegate.currentConfiguration.uri;
  }

  testWidgets('analytics room falls back to the joined parent course', (
    tester,
  ) async {
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              analyticsRoomId: roomUpdate(type: PangeaRoomTypes.analytics),
              courseId: JoinedRoomUpdate(
                state: [
                  stateEvent(
                    type: EventTypes.RoomCreate,
                    content: {'type': 'm.space'},
                  ),
                  stateEvent(
                    type: EventTypes.SpaceChild,
                    stateKey: analyticsRoomId,
                    content: {
                      'via': ['example.com'],
                    },
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );

    final uri = await tapNotification(tester, analyticsRoomId);
    expect(activeSpaceIdFor(uri), courseId);
    expect(parseOpenPanels(uri).left.any((t) => t.type.isRoomPanel), isFalse);
  });

  testWidgets('analytics room with no parent course falls back to the map', (
    tester,
  ) async {
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              orphanAnalyticsRoomId: roomUpdate(
                type: PangeaRoomTypes.analytics,
              ),
            },
          ),
        ),
      ),
    );

    final uri = await tapNotification(tester, orphanAnalyticsRoomId);
    expect(uri.path, '/');
    expect(parseOpenPanels(uri).left, isEmpty);
  });

  testWidgets('a normal joined room still opens as a chat', (tester) async {
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(join: {normalRoomId: roomUpdate()}),
        ),
      ),
    );

    final uri = await tapNotification(tester, normalRoomId);
    final left = parseOpenPanels(uri).left;
    expect(left.any((t) => t.type.isRoomPanel), isTrue);
  });
}
