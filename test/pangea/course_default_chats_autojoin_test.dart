import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat_list/default_chats_room_extension.dart';
import 'get_test_client.dart';

/// A course's default chats (introductions, announcements) are joined for
/// every member when the course page opens (#9031), so nobody misses what is
/// posted in them because they never opened the chat list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const courseRoomId = '!course:fakeServer.notExisting';
  const introAlias =
      '#${SpaceConstants.introductionChatAlias}_course_1:'
      'fakeServer.notExisting';
  const announcementsAlias =
      '#${SpaceConstants.announcementsChatAlias}_course_1:'
      'fakeServer.notExisting';

  /// The key [FakeMatrixApi] files a request under: the path after `/_matrix`
  /// — normalized by [Uri] exactly as the request URL is — plus its query.
  String action(String path, [String query = '']) {
    final url = Uri.parse('https://fakeserver.notexisting/_matrix$path');
    return '${url.path.split('/_matrix').last}${query.isEmpty ? '' : '?$query'}';
  }

  final hierarchyPath =
      '/client/v1/rooms/${Uri.encodeComponent(courseRoomId)}/hierarchy';
  final firstPage = action(hierarchyPath, 'limit=100&max_depth=1');
  final secondPage = action(hierarchyPath, 'limit=100&max_depth=1&from=page2');

  late Client client;
  late FakeMatrixApi api;
  late List<String> joinedAliases;
  late List<String> hierarchyRequests;

  setUp(() async {
    client = await getTestClient();
    api = FakeMatrixApi.currentApi!;
    joinedAliases = [];
    hierarchyRequests = [];
  });

  tearDown(() async {
    await client.dispose();
  });

  Map<String, dynamic> chunk(String roomId, {String? alias}) => {
    'room_id': roomId,
    'num_joined_members': 1,
    'world_readable': true,
    'guest_can_join': false,
    'children_state': <dynamic>[],
    'canonical_alias': ?alias,
  };

  /// Serves [pages] of hierarchy children, recording each page requested.
  void stubHierarchy(Map<String, Map<String, dynamic>> pages) {
    for (final entry in pages.entries) {
      api.api['GET']![entry.key] = (_) {
        hierarchyRequests.add(entry.key);
        return entry.value;
      };
    }
  }

  String joinAction(String alias) =>
      action('/client/v3/join/${Uri.encodeComponent(alias)}');

  void stubJoin(String alias) {
    api.api['POST']![joinAction(alias)] = (_) {
      joinedAliases.add(alias);
      return {'room_id': '!joined:fakeServer.notExisting'};
    };
  }

  Event stateEvent(
    Room room, {
    required String type,
    required Map<String, dynamic> content,
    String stateKey = '',
  }) => Event(
    type: type,
    content: content,
    stateKey: stateKey,
    senderId: userId,
    eventId: '\$${type}_$stateKey',
    originServerTs: DateTime.utc(2026, 1, 1),
    room: room,
  );

  /// The course space, registered on the client so `pangeaSpaceChildren`
  /// (which scans `client.rooms`) can see its joined children.
  Room courseSpace({List<String> childIds = const []}) {
    final space = Room(
      id: courseRoomId,
      client: client,
      membership: Membership.join,
    );
    space.setState(
      stateEvent(
        space,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    for (final childId in childIds) {
      space.setState(
        stateEvent(
          space,
          type: EventTypes.SpaceChild,
          content: {
            'via': ['fakeServer.notExisting'],
          },
          stateKey: childId,
        ),
      );
    }
    client.rooms.add(space);
    return space;
  }

  /// A joined child of the course, carrying [alias] as its canonical alias —
  /// which is what marks it as a default chat.
  void joinedChild(String roomId, String alias) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomCanonicalAlias,
        content: {'alias': alias},
      ),
    );
    client.rooms.add(room);
  }

  test('joins the course default chats it is not already in', () async {
    final space = courseSpace();
    stubHierarchy({
      firstPage: {
        'rooms': [
          chunk(courseRoomId),
          chunk('!intro:fakeServer.notExisting', alias: introAlias),
          chunk('!announce:fakeServer.notExisting', alias: announcementsAlias),
          chunk('!other:fakeServer.notExisting', alias: '#other:fakeServer'),
        ],
      },
    });
    stubJoin(introAlias);
    stubJoin(announcementsAlias);

    await space.joinDefaultChats();

    expect(joinedAliases, unorderedEquals([introAlias, announcementsAlias]));
  });

  test('makes no request when both default chats are already joined', () async {
    joinedChild('!intro:fakeServer.notExisting', introAlias);
    joinedChild('!announce:fakeServer.notExisting', announcementsAlias);
    final space = courseSpace(
      childIds: const [
        '!intro:fakeServer.notExisting',
        '!announce:fakeServer.notExisting',
      ],
    );

    await space.joinDefaultChats();

    expect(hierarchyRequests, isEmpty);
    expect(joinedAliases, isEmpty);
  });

  test('pages past a first page of activity sessions to find them', () async {
    final space = courseSpace();
    stubHierarchy({
      firstPage: {
        'rooms': [chunk('!session:fakeServer.notExisting')],
        'next_batch': 'page2',
      },
      secondPage: {
        'rooms': [
          chunk('!intro:fakeServer.notExisting', alias: introAlias),
          chunk('!announce:fakeServer.notExisting', alias: announcementsAlias),
        ],
      },
    });
    stubJoin(introAlias);
    stubJoin(announcementsAlias);

    await space.joinDefaultChats();

    expect(hierarchyRequests, [firstPage, secondPage]);
    expect(joinedAliases, unorderedEquals([introAlias, announcementsAlias]));
  });

  test('a failed join does not stop the other one', () async {
    final space = courseSpace();
    stubHierarchy({
      firstPage: {
        'rooms': [
          chunk('!intro:fakeServer.notExisting', alias: introAlias),
          chunk('!announce:fakeServer.notExisting', alias: announcementsAlias),
        ],
      },
    });
    api.api['POST']![joinAction(introAlias)] = (_) => {
      'errcode': 'M_FORBIDDEN',
      'error': 'nope',
    };
    stubJoin(announcementsAlias);

    await space.joinDefaultChats();

    expect(joinedAliases, [announcementsAlias]);
  });
}
