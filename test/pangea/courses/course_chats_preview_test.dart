import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_chats_preview.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// Coverage for #9183: the course page's Chats section shows only when it
/// has something in it, and its "See all" only when the All chats subpage
/// holds a chat the section does not — more joined chats than fit, an
/// invite, or a group chat the user can join. An admin keeps the section,
/// since it is where they create the course's chats.
///
/// The hierarchy request that finds a joinable group chat goes through the
/// test client's database, which never answers under the widget tester's
/// fake clock, so these cases all run with nothing joinable. What counts as
/// joinable is covered in course_hierarchy_extension_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const courseId = '!course:fakeServer.notExisting';

  setUpAll(() async {
    // `Avatar` resolves the bot name at build time, which reads GetStorage
    // (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('course_chats');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': '@bot:example.org',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    MatrixState.pangeaController = FakePangeaController();
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
  }) => room.setState(
    Event(
      type: type,
      content: content,
      stateKey: stateKey,
      senderId: userId,
      eventId: '\$$type$stateKey',
      originServerTs: DateTime.now(),
      room: room,
    ),
  );

  /// The course space, with [childIds] as its children. The viewer is an
  /// admin when [admin], else a plain member.
  Room courseRoom({required List<String> childIds, bool admin = false}) {
    final room = Room(
      id: courseId,
      client: client,
      membership: Membership.join,
    );
    setStateEvent(room, EventTypes.RoomCreate, content: {'type': 'm.space'});
    setStateEvent(
      room,
      EventTypes.RoomPowerLevels,
      content: {
        ...RoomDefaults.defaultPowerLevelsContent(),
        'users': {if (admin) userId: SpaceConstants.powerLevelOfAdmin},
      },
    );
    for (final childId in childIds) {
      setStateEvent(
        room,
        EventTypes.SpaceChild,
        content: {
          'via': ['fakeServer.notExisting'],
        },
        stateKey: childId,
      );
    }
    client.rooms.add(room);
    return room;
  }

  /// A child chat of the course in `client.rooms`, with [membership].
  void courseChat(String roomId, {Membership membership = Membership.join}) {
    final room = Room(id: roomId, client: client, membership: membership);
    setStateEvent(room, EventTypes.RoomName, content: {'name': roomId});
    client.rooms.add(room);
  }

  List<String> chatIds(int count) => [
    for (var i = 0; i < count; i++) '!chat$i:fakeServer.notExisting',
  ];

  Future<void> pumpPreview(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: CourseChatsPreview(
                room: room,
                onShowAll: () {},
                onCreateChat: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading.
    await tester.pumpAndSettle();
  }

  Finder sectionHeader() => find.text('Chats');
  Finder seeAll() => find.text('See all');
  Finder createChat() => find.byTooltip('Create group chat');

  testWidgets('a learner with no chats gets no section at all', (tester) async {
    await pumpPreview(tester, courseRoom(childIds: []));

    expect(sectionHeader(), findsNothing);
    expect(seeAll(), findsNothing);
  });

  testWidgets('one or two chats show without See all', (tester) async {
    final ids = chatIds(CourseChatsPreview.maxChats);
    ids.forEach(courseChat);
    await pumpPreview(tester, courseRoom(childIds: ids));

    expect(sectionHeader(), findsOneWidget);
    expect(find.byType(ChatListItem), findsNWidgets(ids.length));
    // Every joined chat is already on screen; the subpage would repeat them.
    expect(seeAll(), findsNothing);
  });

  testWidgets('more chats than fit add See all', (tester) async {
    final ids = chatIds(CourseChatsPreview.maxChats + 1);
    ids.forEach(courseChat);
    await pumpPreview(tester, courseRoom(childIds: ids));

    expect(
      find.byType(ChatListItem),
      findsNWidgets(CourseChatsPreview.maxChats),
    );
    expect(seeAll(), findsOneWidget);
  });

  testWidgets('an invite to a course chat adds See all', (tester) async {
    const invited = '!invited:fakeServer.notExisting';
    courseChat(invited, membership: Membership.invite);
    await pumpPreview(tester, courseRoom(childIds: [invited]));

    // Only joined chats are rows; the invite is answered on the subpage.
    expect(find.byType(ChatListItem), findsNothing);
    expect(seeAll(), findsOneWidget);
  });

  testWidgets('an admin with no chats keeps the section to create one', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(childIds: [], admin: true));

    expect(sectionHeader(), findsOneWidget);
    expect(createChat(), findsOneWidget);
    expect(seeAll(), findsNothing);
  });
}
