import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat_list/course_hierarchy_extension.dart';
import '../get_test_client.dart';

/// What the course page's Chats section counts as a group chat the user can
/// join (#9183) — the same hierarchy children the All chats subpage lists
/// under its group chats, since "See all" promises that subpage has them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const courseId = '!course:fakeServer.notExisting';
  const teacherChat = '!teacherchat:fakeServer.notExisting';

  /// The key [FakeMatrixApi] files a request under: the path after `/_matrix`
  /// — normalized by [Uri] exactly as the request URL is — plus its query.
  String action(String query) {
    final url = Uri.parse(
      'https://fakeserver.notexisting/_matrix/client/v1/rooms/'
      '${Uri.encodeComponent(courseId)}/hierarchy',
    );
    return '${url.path.split('/_matrix').last}?$query';
  }

  final firstPage = action('limit=100&max_depth=1');
  final secondPage = action('limit=100&max_depth=1&from=page2');

  late Client client;
  late FakeMatrixApi api;
  late List<String> hierarchyRequests;

  setUp(() async {
    client = await getTestClient();
    api = FakeMatrixApi.currentApi!;
    hierarchyRequests = [];
  });

  tearDown(() async {
    await client.dispose();
  });

  Map<String, Object?> chunk(String roomId, {String? roomType}) => {
    'room_id': roomId,
    'room_type': ?roomType,
    'num_joined_members': 1,
    'world_readable': false,
    'guest_can_join': false,
    'children_state': <Object?>[],
  };

  /// Serves [pages] of hierarchy children, recording each page requested.
  void stubHierarchy(Map<String, Map<String, Object?>> pages) {
    for (final entry in pages.entries) {
      api.api['GET']![entry.key] = (_) {
        hierarchyRequests.add(entry.key);
        return entry.value;
      };
    }
  }

  Event stateEvent(
    Room room, {
    required String type,
    required Map<String, Object?> content,
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

  /// The course space, with [unsuggested] children marked not suggested.
  Room courseSpace({List<String> unsuggested = const []}) {
    final space = Room(
      id: courseId,
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
    for (final childId in unsuggested) {
      space.setState(
        stateEvent(
          space,
          type: EventTypes.SpaceChild,
          content: {
            'via': ['fakeServer.notExisting'],
            'suggested': false,
          },
          stateKey: childId,
        ),
      );
    }
    client.rooms.add(space);
    return space;
  }

  test('an unjoined group chat in the course is joinable', () async {
    stubHierarchy({
      firstPage: {
        'rooms': [chunk(courseId, roomType: 'm.space'), chunk(teacherChat)],
      },
    });

    expect(await courseSpace().joinableGroupChats(limit: 1), hasLength(1));
  });

  test('sessions, analytics, unsuggested and joined rooms are not', () async {
    const session = '!session:fakeServer.notExisting';
    const analytics = '!analytics:fakeServer.notExisting';
    const unsuggested = '!unsuggested:fakeServer.notExisting';
    const joined = '!joined:fakeServer.notExisting';
    client.rooms.add(
      Room(id: joined, client: client, membership: Membership.join),
    );
    stubHierarchy({
      firstPage: {
        'rooms': [
          chunk(courseId, roomType: 'm.space'),
          chunk(
            session,
            roomType: '${PangeaRoomTypes.activitySession}:activity1',
          ),
          chunk(analytics, roomType: PangeaRoomTypes.analytics),
          chunk(unsuggested),
          chunk(joined),
        ],
      },
    });

    final space = courseSpace(unsuggested: const [unsuggested]);

    expect(await space.joinableGroupChats(limit: 1), isEmpty);
  });

  test('a chat left behind is joinable again', () async {
    client.rooms.add(
      Room(id: teacherChat, client: client, membership: Membership.leave),
    );
    stubHierarchy({
      firstPage: {
        'rooms': [chunk(teacherChat)],
      },
    });

    expect(await courseSpace().joinableGroupChats(limit: 1), hasLength(1));
  });

  test('pages on to find one, and stops once it has', () async {
    final thirdPage = action('limit=100&max_depth=1&from=page3');
    stubHierarchy({
      firstPage: {
        'rooms': [
          chunk(
            '!session:fakeServer.notExisting',
            roomType: '${PangeaRoomTypes.activitySession}:activity1',
          ),
        ],
        'next_batch': 'page2',
      },
      secondPage: {
        'rooms': [chunk(teacherChat)],
        'next_batch': 'page3',
      },
      thirdPage: {'rooms': <Object?>[]},
    });

    expect(
      (await courseSpace().joinableGroupChats(limit: 1)).map((c) => c.roomId),
      [teacherChat],
    );
    expect(hierarchyRequests, [firstPage, secondPage]);
  });

  test('a failed request is the caller\'s to handle', () async {
    api.api['GET']![firstPage] = (_) => {
      'errcode': 'M_UNKNOWN',
      'error': 'hierarchy down',
    };

    await expectLater(
      courseSpace().joinableGroupChats(limit: 1),
      throwsA(isA<MatrixException>()),
    );
  });
}
