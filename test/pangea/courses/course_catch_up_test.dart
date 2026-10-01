import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_badge.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_catch_up.dart';
import '../get_test_client.dart';

/// The Catch up card after #8462 split join requests out of it: it still rolls
/// up what the user can merely catch up on — here, a course chat's unread
/// messages, under the bell and "Mark all read" — and no longer claims the
/// knocks, which now carry their own card and their own glyph.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const knockerId = '@knocker:fakeServer.notExisting';
  const pingerId = '@pinger:fakeServer.notExisting';
  const pingerName = 'Pia Pinger';
  const chatId = '!chat:fakeServer.notExisting';
  const chatName = 'Introductions';

  setUpAll(() {
    // `Avatar` resolves the bot name from the environment at build time.
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    // The ping cache is a static ValueNotifier shared across cases.
    CoursePingBadgeCache.instance.value = null;
    await client.dispose();
  });

  void pingThisCourse({String courseId = '!course:fakeServer.notExisting'}) =>
      CoursePingBadgeCache.instance.value = (
        courseId: courseId,
        activityId: 'activity-1',
        sessionRoomId: '!session:fakeServer.notExisting',
        senderId: pingerId,
      );

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

  /// A course space with one knocking user and one joined child chat holding
  /// [unread] unread messages.
  Room courseRoom({required int unread}) {
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
      EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': pingerName},
      stateKey: pingerId,
      senderId: pingerId,
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
      notificationCount: unread,
    );
    setStateEvent(chat, EventTypes.RoomCreate, content: {});
    setStateEvent(chat, EventTypes.RoomName, content: {'name': chatName});
    client.rooms.add(chat);
    return course;
  }

  Future<void> pumpCatchUp(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 360, child: CourseCatchUp(room: room)),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the card isn't in
    // the tree until localizations finish loading.
    await tester.pumpAndSettle();
  }

  testWidgets('unread course chats still roll up under the bell', (
    tester,
  ) async {
    await pumpCatchUp(tester, courseRoom(unread: 3));

    final context = tester.element(find.byType(CourseCatchUp));
    final l10n = L10n.of(context);
    expect(find.text(l10n.catchUp), findsOneWidget);
    expect(find.text(l10n.countNewMessages(3)), findsOneWidget);
    expect(find.text(chatName), findsOneWidget);
    expect(find.text(l10n.markAllRead), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('a course ping rolls up here, above the unread chats', (
    tester,
  ) async {
    pingThisCourse();
    await pumpCatchUp(tester, courseRoom(unread: 3));

    final context = tester.element(find.byType(CourseCatchUp));
    final l10n = L10n.of(context);
    expect(find.text(l10n.pingedActivity), findsOneWidget);
    // The card shows two rows before its expander, so the ping leading is the
    // difference between seeing it and having to tap for it.
    expect(
      tester.getTopLeft(find.text(l10n.pingedActivity)).dy,
      lessThan(tester.getTopLeft(find.text(l10n.countNewMessages(3))).dy),
    );
  });

  testWidgets('a course ping alone opens the card', (tester) async {
    // Nothing else pending: the ping is enough to make the card render, and
    // the plan has not hydrated, so the row stands on its label alone.
    pingThisCourse();
    await pumpCatchUp(tester, courseRoom(unread: 0));

    final context = tester.element(find.byType(CourseCatchUp));
    final l10n = L10n.of(context);
    expect(find.text(l10n.catchUp), findsOneWidget);
    expect(find.byType(CoursePingBadge), findsOneWidget);
    // Who is waiting, and what for. The plan has not hydrated here, so the
    // activity falls back to its label while the name of the coursemate --
    // which comes off the course's own member list, not the ping body --
    // is there either way.
    expect(find.text(pingerName), findsOneWidget);
    expect(find.text(l10n.pingedActivity), findsOneWidget);
  });

  testWidgets('another course\'s ping does not appear here', (tester) async {
    pingThisCourse(courseId: '!other:fakeServer.notExisting');
    await pumpCatchUp(tester, courseRoom(unread: 0));

    final context = tester.element(find.byType(CourseCatchUp));
    final l10n = L10n.of(context);
    expect(find.text(l10n.catchUp), findsNothing);
    expect(find.text(l10n.pingedActivity), findsNothing);
  });

  testWidgets('a pending knock no longer appears here', (tester) async {
    // It moved to CourseKnockRequests — a decision, not something to mark
    // read. With nothing else pending the card renders nothing at all.
    await pumpCatchUp(tester, courseRoom(unread: 0));

    final context = tester.element(find.byType(CourseCatchUp));
    final l10n = L10n.of(context);
    expect(find.text(l10n.catchUp), findsNothing);
    expect(find.text(l10n.knocking), findsNothing);
    expect(find.byIcon(KnockingUsersBadge.icon), findsNothing);
  });
}
