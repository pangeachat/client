import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/catch_up_dismissal_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_catch_up.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../get_test_client.dart';

/// Coverage for the course page's Catch up section (#8357): the in-course
/// knock review surface (the avatar badges elsewhere point the admin here).
/// It must list the knocker with an Approve action for admins — live via
/// KnockingUsersBuilder — and stay hidden entirely for non-admins (knock
/// review is admin-only by design).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const knockerId = '@knocker:fakeServer.notExisting';

  setUpAll(() {
    // `Avatar` inside the knock row resolves the bot name from the environment
    // at build time; initialize dotenv inline so no real `.env` is needed.
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// A course space with one user knocking on it. [ownPowerLevel] decides
  /// whether the viewer is the admin who can act on that knock.
  Room courseRoom({required int ownPowerLevel}) {
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    // A real course room IS a space — the card reads `spaceChildren` (for
    // the unread-chat rollups), which the SDK gates on `isSpace`.
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': 'm.space'},
        stateKey: '',
        senderId: userId,
        eventId: '\$create',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
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
        type: EventTypes.RoomMember,
        content: {'membership': 'knock'},
        stateKey: knockerId,
        senderId: knockerId,
        eventId: '\$knock',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    return room;
  }

  Future<void> pumpCatchUp(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 360, child: CourseCatchUp(room: room)),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the card isn't in
    // the tree until localizations finish loading.
    await tester.pumpAndSettle();
  }

  testWidgets('an admin sees the knocking user with an Approve action', (
    tester,
  ) async {
    await pumpCatchUp(
      tester,
      courseRoom(ownPowerLevel: SpaceConstants.powerLevelOfAdmin),
    );

    final context = tester.element(find.byType(CourseCatchUp));
    expect(find.text(L10n.of(context).catchUp), findsOneWidget);
    expect(find.text(L10n.of(context).knocking), findsOneWidget);
    expect(find.text(L10n.of(context).approve), findsOneWidget);
  });

  testWidgets('a dismissed knock stays out of the card', (tester) async {
    // The dismissal layer (#8357 "Mark all read"): per-room account data
    // holding the knock keys the user marked read. The knock stays pending
    // everywhere else; only the card filters on it.
    final room = courseRoom(ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
    final knocker = room.getParticipants([Membership.knock]).single;
    room.roomAccountData[PangeaEventTypes.dismissedCatchUp] = BasicEvent(
      type: PangeaEventTypes.dismissedCatchUp,
      content: {
        'keys': [CatchUpDismissalExtension.knockKey(room, knocker)],
      },
    );
    await pumpCatchUp(tester, room);

    final context = tester.element(find.byType(CourseCatchUp));
    expect(find.text(L10n.of(context).catchUp), findsNothing);
    expect(find.text(L10n.of(context).approve), findsNothing);
  });

  testWidgets('a non-admin sees no Catch up card at all', (tester) async {
    await pumpCatchUp(tester, courseRoom(ownPowerLevel: 0));

    final context = tester.element(find.byType(CourseCatchUp));
    expect(find.text(L10n.of(context).catchUp), findsNothing);
    expect(find.text(L10n.of(context).approve), findsNothing);
  });
}
