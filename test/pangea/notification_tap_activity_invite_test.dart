import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';

/// #9251 — tapping the notification for an invite to an activity session
/// opens that activity's page with the session bound, never the room (the
/// chat view would join the invite as it builds) and never the parent course
/// card (joining-courses.instructions.md).
void main() {
  sqfliteFfiInit();

  const sessionId = '!invitedsession:example.com';
  const courseId = '!invitecourse:example.com';
  const activityId = 'activity-9251';

  late Client client;

  setUp(() async {
    client = await getTestClient();
    FakeMatrixApi.client = client;
  });

  testWidgets('an activity-session invite opens the activity page', (
    tester,
  ) async {
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              // A joined parent course: before #9251 the invite landed on its
              // course card instead of the activity.
              courseId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.RoomCreate,
                    content: {'type': 'm.space'},
                    stateKey: '',
                    senderId: '@teacher:example.com',
                    eventId: '\$create:example.com',
                    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
                  ),
                  MatrixEvent(
                    type: EventTypes.SpaceChild,
                    content: {
                      'via': ['example.com'],
                    },
                    stateKey: sessionId,
                    senderId: '@teacher:example.com',
                    eventId: '\$child:example.com',
                    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
                  ),
                ],
              ),
            },
            invite: {
              sessionId: InvitedRoomUpdate(
                inviteState: [
                  StrippedStateEvent(
                    type: EventTypes.RoomCreate,
                    content: {
                      'type': '${PangeaRoomTypes.activitySession}:$activityId',
                    },
                    stateKey: '',
                    senderId: '@friend:example.com',
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );

    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => NotificationTapUtil.handleNotificationTap(
        client: client,
        roomId: sessionId,
        notification: {'type': EventTypes.RoomMember},
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    final uri = router.routerDelegate.currentConfiguration.uri;
    final left = parseOpenPanels(uri).left;
    expect(left, hasLength(1));
    expect(left.single.type, PanelTypesEnum.activity);
    final param = (left.single as ActivityPanelToken).param!;
    expect(param.activityId, activityId);
    expect(param.roomId, sessionId);
    expect(activeSpaceIdFor(uri), isNull);
  });
}
