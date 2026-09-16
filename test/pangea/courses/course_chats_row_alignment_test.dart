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
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/routes/chat_list/course_default_chats_enum.dart';
import 'package:fluffychat/routes/chat_list/default_chat_creation_tile.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// #9086 — a course's Chats list interleaves [DefaultChatCreationTile]
/// suggestion rows with [ChatListItem] chat rows, so the two have to share a
/// left edge. They did not: the chat rows set an 8px `contentPadding` and the
/// creation rows took the `ListTile` default of 16, pushing the dashed "+"
/// placeholder and the suggestion titles right of the column below them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const chatName = 'Library registration roleplay';

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

  /// A course space the viewer administers, with neither default chat created
  /// nor dismissed — so both creation rows show.
  Room courseRoom() {
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    setStateEvent(room, EventTypes.RoomCreate, content: {'type': 'm.space'});
    setStateEvent(
      room,
      EventTypes.RoomPowerLevels,
      content: {
        ...RoomDefaults.defaultPowerLevelsContent(),
        'users': {userId: SpaceConstants.powerLevelOfAdmin},
      },
    );
    return room;
  }

  Room chatRoom() {
    final room = Room(
      id: '!chat:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    setStateEvent(room, EventTypes.RoomName, content: {'name': chatName});
    return room;
  }

  Future<void> pumpRows(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultChatCreationTile(
                  space: courseRoom(),
                  type: CourseDefaultChatsEnum.introductions,
                ),
                ChatListItem(chatRoom(), onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The creation row's dashed placeholder — the `CustomPaint` box wrapping
  /// its "+".
  Finder creationLeading() => find
      .ancestor(of: find.byIcon(Icons.add), matching: find.byType(CustomPaint))
      .first;

  Finder chatLeading() => find.byType(Avatar);

  testWidgets('creation rows share the chat rows left edge', (tester) async {
    await pumpRows(tester);

    expect(
      tester.getRect(creationLeading()).left,
      tester.getRect(chatLeading()).left,
      reason: 'the dashed placeholder sits on the avatar column',
    );
    expect(
      tester.getRect(find.text('Create Introductions Chat')).left,
      tester.getRect(find.text(chatName)).left,
      reason: 'the suggestion title sits on the chat titles',
    );
  });

  testWidgets('the dashed placeholder is avatar-sized', (tester) async {
    await pumpRows(tester);

    // Both boxes are `Avatar.defaultSize`, and the placeholder's 1.5px stroke
    // is centred on that boundary — so the dashes read as a circle of the same
    // diameter as the avatar beside them, not a larger or smaller one.
    expect(
      tester.getSize(creationLeading()),
      const Size(Avatar.defaultSize, Avatar.defaultSize),
    );
    expect(
      tester.getSize(chatLeading()),
      const Size(Avatar.defaultSize, Avatar.defaultSize),
    );
  });
}
