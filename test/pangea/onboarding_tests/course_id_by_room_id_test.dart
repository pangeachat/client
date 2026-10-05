import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';
import '../get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = '!claimed:fakeServer.notExisting';
  const courseId = 'quest-uuid';

  late Client client;

  setUp(() async {
    // Mirrors the app client (client_manager.dart), which keeps the course
    // plan for a room that arrives by sync.
    client = await getTestClient(
      importantStateEvents: {PangeaEventTypes.coursePlan},
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<void> sync(String batch, List<MatrixEvent> state) => client.handleSync(
    SyncUpdate(
      nextBatch: batch,
      rooms: RoomsUpdate(join: {roomId: JoinedRoomUpdate(state: state)}),
    ),
  );

  MatrixEvent member() => MatrixEvent(
    type: EventTypes.RoomMember,
    content: {'membership': 'join'},
    stateKey: client.userID,
    senderId: client.userID!,
    eventId: '\$member',
    originServerTs: DateTime.now(),
  );

  MatrixEvent coursePlan() => MatrixEvent(
    type: PangeaEventTypes.coursePlan,
    content: {'uuid': courseId, 'l2': 'es'},
    stateKey: '',
    senderId: client.userID!,
    eventId: '\$coursePlan',
    originServerTs: DateTime.now(),
  );

  // #9368: a claimed course's join synced before its course plan, and the
  // lookup read the plan straight away because the user was already joined.
  test('waits for a course plan that syncs after the join', () async {
    await sync('b1', [member()]);
    expect(client.getRoomById(roomId)?.membership, Membership.join);

    final lookup = client.getCourseIdByRoomId(roomId);
    await sync('b2', [coursePlan()]);

    expect(await lookup, courseId);
  });

  test('returns at once when the course plan is already there', () async {
    await sync('b1', [member(), coursePlan()]);

    expect(await client.getCourseIdByRoomId(roomId), courseId);
  });
}
