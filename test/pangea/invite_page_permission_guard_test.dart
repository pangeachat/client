import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';
import 'package:fluffychat/widgets/users/member_actions.dart';
import 'get_test_client.dart';
import 'invite_page_harness.dart';

/// #8694 / CLIENT-DCA — the invite page is URL-addressable, so hiding the
/// entry buttons (#7875) never kept a member without invite power out of it,
/// and every invite they attempted failed with M_FORBIDDEN. The page stays
/// browsable as a roster; without `canInvite` the invite affordances disable
/// and a note says why. Approving a knock issues an invite, so the shared
/// member-actions "Approve" hides on the same condition.

void main() {
  const userId = '@test:fakeServer.notExisting';
  const roomId = '!session:fakeServer.notExisting';
  const guardNote = "You don't have permission to invite members here.";

  late Client client;
  late InvitePageHarness harness;

  setUpAll(() async {
    harness = await InvitePageHarness.create();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// A joined room whose power levels use the course defaults (`invite: 50`),
  /// with the viewer at [ownPowerLevel]. It already has a join code (see
  /// [InvitePageHarness.pump]).
  Room buildRoom({required int ownPowerLevel}) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: {
          ...RoomDefaults.defaultPowerLevelsContent(),
          'users': {userId: ownPowerLevel},
        },
        stateKey: '',
        senderId: userId,
        eventId: '\$powerLevels',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    room.setState(
      Event(
        type: EventTypes.RoomJoinRules,
        content: {'join_rule': 'knock', 'access_code': 'abc12de'},
        stateKey: '',
        senderId: userId,
        eventId: '\$joinRules',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    client.rooms.add(room);
    return room;
  }

  testWidgets('without invite power the page stays browsable with a note', (
    tester,
  ) async {
    buildRoom(ownPowerLevel: 0);
    await harness.pump(tester, client: client, roomId: roomId);

    expect(find.text(guardNote), findsOneWidget);
    expect(find.byType(PangeaSearchBar), findsOneWidget);
  });

  testWidgets('with invite power there is no note', (tester) async {
    buildRoom(ownPowerLevel: 100);
    await harness.pump(tester, client: client, roomId: roomId);

    expect(find.text(guardNote), findsNothing);
    expect(find.byType(PangeaSearchBar), findsOneWidget);
  });

  group('ApproveMemberAction', () {
    User knocker(Room room) => User(
      '@knocker:fakeServer.notExisting',
      membership: 'knock',
      room: room,
    );

    test('hidden without invite power — approval is an invite', () {
      final room = buildRoom(ownPowerLevel: 0);
      expect(ApproveMemberAction(user: knocker(room)).visible(), false);
    });

    test('visible for a knocking user when the viewer can invite', () {
      final room = buildRoom(ownPowerLevel: 100);
      expect(ApproveMemberAction(user: knocker(room)).visible(), true);
    });

    test('hidden for a joined user regardless of power', () {
      final room = buildRoom(ownPowerLevel: 100);
      final joined = User(
        '@member:fakeServer.notExisting',
        membership: 'join',
        room: room,
      );
      expect(ApproveMemberAction(user: joined).visible(), false);
    });
  });
}
