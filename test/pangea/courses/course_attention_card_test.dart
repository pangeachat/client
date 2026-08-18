import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_badge.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_attention_card.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_catch_up.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_knock_requests.dart';
import '../get_test_client.dart';

/// The two attention cards stack on the course page, so their headers have to
/// read as one ladder: same title size, and leading glyphs that occupy the
/// same box. They mark themselves differently on purpose — an outlined bell
/// for pings to catch up on, a filled "!" disc for pending join requests —
/// and a filled shape already reads heavier than an outline, so a size
/// difference on top of that makes the whole header look bigger (#8462).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const knockerId = '@knocker:fakeServer.notExisting';
  const chatId = '!chat:fakeServer.notExisting';

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  void setStateEvent(
    Room room,
    String type, {
    required Map<String, Object?> content,
    String stateKey = '',
    String? senderId,
  }) => room.setState(
    Event(
      type: type,
      content: content,
      stateKey: stateKey,
      senderId: senderId ?? userId,
      eventId: '\$$type$stateKey',
      originServerTs: DateTime.now(),
      room: room,
    ),
  );

  /// A course with both cards showing at once: someone knocking, and a child
  /// chat holding unread messages.
  Room courseRoom() {
    final course = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    setStateEvent(course, EventTypes.RoomCreate, content: {'type': 'm.space'});
    setStateEvent(
      course,
      EventTypes.RoomPowerLevels,
      content: {
        ...RoomDefaults.defaultPowerLevelsContent(),
        'users': {userId: SpaceConstants.powerLevelOfAdmin},
      },
    );
    setStateEvent(
      course,
      EventTypes.RoomMember,
      content: {'membership': 'knock', 'displayname': 'Kai Knocker'},
      stateKey: knockerId,
      senderId: knockerId,
    );
    setStateEvent(
      course,
      EventTypes.SpaceChild,
      content: {
        'via': ['fakeServer.notExisting'],
      },
      stateKey: chatId,
    );

    final chat = Room(
      id: chatId,
      client: client,
      membership: Membership.join,
      notificationCount: 2,
    );
    setStateEvent(chat, EventTypes.RoomCreate, content: {});
    setStateEvent(
      chat,
      EventTypes.RoomName,
      content: {'name': 'Introductions'},
    );
    client.rooms.add(chat);
    return course;
  }

  /// Both cards over one room, stacked exactly as the course page stacks them.
  Future<void> pumpBothCards(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CourseKnockRequests(room: room),
                  CourseCatchUp(room: room),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('both headers are set at the same size', (tester) async {
    await pumpBothCards(tester, courseRoom());

    final context = tester.element(find.byType(CourseKnockRequests));
    final l10n = L10n.of(context);
    final knockTitle = tester.widget<Text>(
      find.text(l10n.usersAreTryingToJoinCourse),
    );
    final catchUpTitle = tester.widget<Text>(find.text(l10n.catchUp));

    expect(knockTitle.style?.fontSize, isNotNull);
    expect(knockTitle.style?.fontSize, catchUpTitle.style?.fontSize);
    expect(knockTitle.style?.fontWeight, catchUpTitle.style?.fontWeight);
  });

  testWidgets('both leading glyphs occupy the same box', (tester) async {
    await pumpBothCards(tester, courseRoom());

    // The knock disc: its painted circle, not the inset glyph inside it.
    final knockGlyph = tester.getSize(
      find.ancestor(
        of: find.byIcon(KnockingUsersBadge.icon),
        matching: find.byType(CircleAvatar),
      ),
    );
    final bell = tester.getSize(find.byIcon(Icons.notifications_outlined));

    expect(knockGlyph, bell);
    expect(
      knockGlyph,
      const Size(CourseAttentionCard.iconSize, CourseAttentionCard.iconSize),
    );
  });
}
