import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/common/widgets/course_avatar.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_builder.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import '../get_test_client.dart';

/// Coverage for #8246: mobile has no nav rail, so the courses list is where a
/// course admin learns that someone is knocking. The rail's red "!" badge has
/// to reach the list tiles too — admin-only, and only for tiles that have a
/// real course room behind them.
///
/// The tiles here deliberately leave `unreadCoursePingEvent` null: the badged
/// branch of [CourseAvatar] sits under an `UnreadRoomsBadge`, which needs a
/// mounted `MatrixState` these tests don't have. What is under test is the
/// wiring — which tiles get a [KnockingUsersBuilder], and what the builder's
/// answer does to the tile — so the avatar's own flag and the tile's announced
/// label are the assertions.
class _StubCourseTileContent extends AddCourseTileContent {
  @override
  final Room? space;

  _StubCourseTileContent({this.space});

  @override
  String title(L10n l10n) => 'Elementary German I';

  @override
  int? get members => 12;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const knockerId = '@knocker:fakeServer.notExisting';

  setUpAll(() {
    // `Avatar` inside `CourseAvatar` resolves the bot name from the environment
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

  Future<void> pumpList(
    WidgetTester tester,
    AddCourseTileContent content,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: AddCourseTileList(content: [content], onTap: (_) {}),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the tile isn't in
    // the tree until localizations finish loading.
    await tester.pumpAndSettle();
  }

  bool avatarIsBadged(WidgetTester tester) =>
      tester.widget<CourseAvatar>(find.byType(CourseAvatar)).hasKnockingUsers;

  testWidgets('a course admin sees the knock badge on the list tile', (
    tester,
  ) async {
    await pumpList(
      tester,
      _StubCourseTileContent(
        space: courseRoom(ownPowerLevel: SpaceConstants.powerLevelOfAdmin),
      ),
    );

    expect(avatarIsBadged(tester), isTrue);

    final context = tester.element(find.byType(AddCourseTile));
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(AddCourseTile),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      semantics.properties.label,
      contains(L10n.of(context).aUserIsKnocking),
      reason: 'the badge is a bare icon; the tile has to say it out loud',
    );
  });

  testWidgets('a non-admin member never sees the knock badge', (tester) async {
    await pumpList(
      tester,
      _StubCourseTileContent(space: courseRoom(ownPowerLevel: 0)),
    );

    expect(avatarIsBadged(tester), isFalse);

    final context = tester.element(find.byType(AddCourseTile));
    expect(
      tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byType(AddCourseTile),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .label,
      isNot(contains(L10n.of(context).aUserIsKnocking)),
    );
  });

  testWidgets('a tile with no room behind it never loads knocking members', (
    tester,
  ) async {
    await pumpList(tester, _StubCourseTileContent());

    expect(
      find.byType(KnockingUsersBuilder),
      findsNothing,
      reason: 'public-course previews have no members to request',
    );
    expect(avatarIsBadged(tester), isFalse);
  });
}
