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
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// Coverage for #9183: the course page's Chats section shows only when it
/// has something in it, and its "See all" only when the All chats subpage
/// holds a chat the section does not — more joined chats than fit, an
/// invite, or a group chat the user can join. An admin keeps the section,
/// since it is where they create the course's chats. Which hierarchy
/// children count as joinable is covered in
/// course_hierarchy_extension_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late FakeMatrixApi api;
  late List<String> hierarchyRequests;

  const userId = '@test:fakeServer.notExisting';
  const courseId = '!course:fakeServer.notExisting';
  const teacherChat = '!teacherchat:fakeServer.notExisting';

  /// The key [FakeMatrixApi] files a course's first hierarchy page under.
  String hierarchyAction(String roomId) {
    final url = Uri.parse(
      'https://fakeserver.notexisting/_matrix/client/v1/rooms/'
      '${Uri.encodeComponent(roomId)}/hierarchy',
    );
    return '${url.path.split('/_matrix').last}?limit=100&max_depth=1';
  }

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
    api = FakeMatrixApi.currentApi!;
    hierarchyRequests = [];
  });

  tearDown(() async {
    await client.dispose();
  });

  Map<String, Object?> hierarchyChild(String roomId, {String? roomType}) => {
    'room_id': roomId,
    'room_type': ?roomType,
    'num_joined_members': 1,
    'world_readable': false,
    'guest_can_join': false,
    'children_state': <Object?>[],
  };

  /// Serves [roomId]'s hierarchy as [children], recording each request.
  void stubHierarchy(
    List<Map<String, Object?>> children, {
    String roomId = courseId,
  }) => api.api['GET']![hierarchyAction(roomId)] = (_) {
    hierarchyRequests.add(roomId);
    return {'rooms': children};
  };

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

  /// A course space with [childIds] as its children. The viewer is an admin
  /// when [admin], else a plain member.
  Room courseRoom({
    required List<String> childIds,
    String id = courseId,
    bool admin = false,
  }) {
    final room = Room(id: id, client: client, membership: Membership.join);
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

  Widget preview(Room room) => MaterialApp(
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
  );

  /// Lets a mounted preview's hierarchy request answer, then settles. The
  /// answer arrives on real time, which the fake clock doesn't advance, so
  /// alternate real waits with frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpPreview(WidgetTester tester, Room room) async {
    await tester.pumpWidget(preview(room));
    // L10n's delegate resolves from a deferred library on the fake clock, and
    // the app builds the preview (which sends its request) only after it.
    await tester.pumpAndSettle();
    await settle(tester);
  }

  Finder sectionHeader() => find.text('Chats');
  Finder seeAll() => find.text('See all');
  Finder createChat() => find.byTooltip('Create group chat');

  testWidgets('a learner with no chats gets no section at all', (tester) async {
    stubHierarchy([]);
    await pumpPreview(tester, courseRoom(childIds: []));

    expect(hierarchyRequests, [courseId]);
    expect(sectionHeader(), findsNothing);
    expect(seeAll(), findsNothing);
  });

  testWidgets('one or two chats show without See all', (tester) async {
    final ids = chatIds(CourseChatsPreview.maxChats);
    ids.forEach(courseChat);
    stubHierarchy([for (final id in ids) hierarchyChild(id)]);
    await pumpPreview(tester, courseRoom(childIds: ids));

    expect(hierarchyRequests, [courseId]);
    expect(sectionHeader(), findsOneWidget);
    expect(find.byType(ChatListItem), findsNWidgets(ids.length));
    // Every joined chat is already on screen; the subpage would repeat them.
    expect(seeAll(), findsNothing);
  });

  testWidgets('more chats than fit add See all without asking the server', (
    tester,
  ) async {
    final ids = chatIds(CourseChatsPreview.maxChats + 1);
    ids.forEach(courseChat);
    stubHierarchy([for (final id in ids) hierarchyChild(id)]);
    await pumpPreview(tester, courseRoom(childIds: ids));

    expect(
      find.byType(ChatListItem),
      findsNWidgets(CourseChatsPreview.maxChats),
    );
    expect(seeAll(), findsOneWidget);
    // The joined chats already decide "See all"; the hierarchy can't change it.
    expect(hierarchyRequests, isEmpty);
  });

  testWidgets('an invite adds See all without asking the server', (
    tester,
  ) async {
    const invited = '!invited:fakeServer.notExisting';
    courseChat(invited, membership: Membership.invite);
    stubHierarchy([]);
    await pumpPreview(tester, courseRoom(childIds: [invited]));

    // Only joined chats are rows; the invite is answered on the subpage.
    expect(find.byType(ChatListItem), findsNothing);
    expect(seeAll(), findsOneWidget);
    expect(hierarchyRequests, isEmpty);
  });

  testWidgets('a group chat the learner can join adds See all', (tester) async {
    final joined = chatIds(1);
    joined.forEach(courseChat);
    stubHierarchy([hierarchyChild(joined.single), hierarchyChild(teacherChat)]);
    await pumpPreview(tester, courseRoom(childIds: [...joined, teacherChat]));

    expect(find.byType(ChatListItem), findsOneWidget);
    expect(seeAll(), findsOneWidget);
  });

  testWidgets('a joinable chat shows the section with no joined chat', (
    tester,
  ) async {
    stubHierarchy([hierarchyChild(teacherChat)]);
    await pumpPreview(tester, courseRoom(childIds: [teacherChat]));

    expect(sectionHeader(), findsOneWidget);
    expect(seeAll(), findsOneWidget);
  });

  testWidgets('unjoined sessions and analytics rooms show no section', (
    tester,
  ) async {
    const session = '!session:fakeServer.notExisting';
    const analytics = '!analytics:fakeServer.notExisting';
    stubHierarchy([
      hierarchyChild(
        session,
        roomType: '${PangeaRoomTypes.activitySession}:activity1',
      ),
      hierarchyChild(analytics, roomType: PangeaRoomTypes.analytics),
    ]);
    await pumpPreview(tester, courseRoom(childIds: [session, analytics]));

    expect(hierarchyRequests, [courseId]);
    expect(sectionHeader(), findsNothing);
  });

  testWidgets('an admin with no chats keeps the section to create one', (
    tester,
  ) async {
    stubHierarchy([]);
    await pumpPreview(tester, courseRoom(childIds: [], admin: true));

    expect(sectionHeader(), findsOneWidget);
    expect(createChat(), findsOneWidget);
    expect(seeAll(), findsNothing);
  });

  testWidgets('a failed hierarchy load still offers the subpage', (
    tester,
  ) async {
    api.api['GET']![hierarchyAction(courseId)] = (_) => {
      'errcode': 'M_UNKNOWN',
      'error': 'hierarchy down',
    };
    await pumpPreview(tester, courseRoom(childIds: []));

    expect(sectionHeader(), findsOneWidget);
    expect(seeAll(), findsOneWidget);
  });

  testWidgets('switching courses drops the previous course answer', (
    tester,
  ) async {
    const otherCourseId = '!other:fakeServer.notExisting';
    stubHierarchy([hierarchyChild(teacherChat)]);
    stubHierarchy([], roomId: otherCourseId);
    await pumpPreview(tester, courseRoom(childIds: [teacherChat]));
    expect(seeAll(), findsOneWidget);

    await tester.pumpWidget(
      preview(courseRoom(childIds: [], id: otherCourseId)),
    );
    await settle(tester);

    expect(hierarchyRequests, [courseId, otherCourseId]);
    expect(sectionHeader(), findsNothing);
  });
}
