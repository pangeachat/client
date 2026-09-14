import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'get_test_client.dart';

/// Regression: Sentry CLIENT-EPX / EP5 / EPY / EP6 (#9019).
///
/// #8379 keeps the signed-out account resolvable so the home route can build
/// through logout, which means course pages, the world-map card and the chat
/// list still build against a client whose `userID` is null. The reads they
/// make have an obvious signed-out answer — nothing completed, no role, not
/// an admin — and must give it rather than throw a null check.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const roomId = '!1234:fakeServer.notExisting';
  const userId = '@test:fakeServer.notExisting';

  /// A client nobody ever logged in on: `userID` is null, exactly as it is
  /// after the SDK's `clear()` runs on logout.
  Future<Client> signedOutClient() async => Client(
    'signed-out',
    httpClient: FakeMatrixApi(),
    database: await MatrixSdkDatabase.init(
      'signed_out',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );

  Room roomWithRole(Client client) {
    final room = Room(id: roomId, client: client);
    final role = ActivityRoleModel(
      id: 'role-1',
      userId: userId,
      role: 'Interviewer',
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

  test('ownRoleState and ownRole are null for a signed-out account', () async {
    final client = await signedOutClient();
    addTearDown(client.dispose);
    expect(client.userID, isNull, reason: 'precondition');

    final room = roomWithRole(client);
    expect(room.ownRoleState, isNull);
    expect(room.ownRole, isNull);
  });

  test('ownRoleState still resolves the signed-in account\'s role', () async {
    final client = await getTestClient();
    addTearDown(client.dispose);

    expect(roomWithRole(client).ownRoleState?.id, 'role-1');
  });

  test('isRoomAdmin is false for a signed-out account', () async {
    final client = await signedOutClient();
    addTearDown(client.dispose);

    expect(Room(id: roomId, client: client).isRoomAdmin, isFalse);
  });

  test('hasCompletedActivity is false without a user id', () {
    expect(
      CourseInfoSummariesModel({}).hasCompletedActivity(null, 'a1'),
      isFalse,
    );
  });
}
