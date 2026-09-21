import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';
import 'sentry_capture_harness.dart';

/// A learner's analytics rooms are added to every course space they are in. A
/// space the server refuses (`M_FORBIDDEN`) refuses every room for the same
/// reason, so the first refusal ends the work on that space: one request and
/// one report, not one of each per analytics room (#9181).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const refusingSpaceId = '!refusing:fakeServer.notExisting';
  const acceptingSpaceId = '!accepting:fakeServer.notExisting';
  const analyticsRoomIds = [
    '!analyticsEs:fakeServer.notExisting',
    '!analyticsFr:fakeServer.notExisting',
    '!analyticsDe:fakeServer.notExisting',
  ];

  final counter = SentryEventCounter();
  late Client client;
  late FakeMatrixApi api;
  late Map<String, int> writes;

  /// The key [FakeMatrixApi] files a state write under: the path after
  /// `/_matrix`, normalized by [Uri] exactly as the request URL is.
  String stateAction(String roomId, String type, String stateKey) {
    final url = Uri.parse(
      'https://fakeserver.notexisting/_matrix/client/v3/rooms/'
      '${Uri.encodeComponent(roomId)}/state/$type/'
      '${Uri.encodeComponent(stateKey)}',
    );
    return url.path.split('/_matrix').last;
  }

  Event stateEvent(
    Room room, {
    required String type,
    required Map<String, dynamic> content,
  }) => Event(
    type: type,
    content: content,
    stateKey: '',
    senderId: userId,
    eventId: '\$${type}_${room.id}',
    originServerTs: DateTime.utc(2026, 1, 1),
    room: room,
  );

  /// A joined room the learner created, of [roomType], registered on the
  /// client. Creating it is what lets them send `m.space.child` into it.
  void joinedRoom(String roomId, String roomType) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomCreate,
        content: {'type': roomType},
      ),
    );
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomPowerLevels,
        content: {
          'users': {userId: 100},
        },
      ),
    );
    client.rooms.add(room);
  }

  /// Answers every space-child write to [spaceId] with [response], counting
  /// them. The matching parent write on the analytics room, which the SDK
  /// makes after a child write succeeds, is always accepted.
  void stubSpace(String spaceId, Map<String, dynamic> response) {
    for (final childId in analyticsRoomIds) {
      api.api['PUT']![stateAction(
        spaceId,
        EventTypes.SpaceChild,
        childId,
      )] = (_) {
        writes[spaceId] = (writes[spaceId] ?? 0) + 1;
        return response;
      };
      api.api['PUT']![stateAction(childId, EventTypes.SpaceParent, spaceId)] =
          (_) => {'event_id': '\$parent'};
    }
  }

  // The pass skips the bot's own account, which it names from the environment.
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('space_fanout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': '@bot:fakeServer.notExisting'});
  });

  setUp(() async {
    await counter.init();
    client = await getTestClient();
    api = FakeMatrixApi.currentApi!;
    writes = {};
    // The refusing space comes first, so the accepting one is only reached if
    // a refusal leaves the rest of the pass alone.
    joinedRoom(refusingSpaceId, RoomCreationTypes.mSpace);
    joinedRoom(acceptingSpaceId, RoomCreationTypes.mSpace);
    for (final roomId in analyticsRoomIds) {
      joinedRoom(roomId, PangeaRoomTypes.analytics);
    }
  });

  tearDown(() async {
    await client.dispose();
    await counter.close();
  });

  test('a refused space costs one write and one report', () async {
    stubSpace(refusingSpaceId, {
      'errcode': 'M_FORBIDDEN',
      'error': 'User $userId not in room $refusingSpaceId',
    });
    stubSpace(acceptingSpaceId, {'event_id': '\$child'});

    // Not awaited: the pass rests for up to ten seconds after a space it wrote
    // to, and the accepting space is the last one.
    unawaited(client.addAnalyticsRoomsToSpaces());
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while ((writes[acceptingSpaceId] ?? 0) < analyticsRoomIds.length &&
        DateTime.now().isBefore(deadline)) {
      await pumpEventQueue();
    }

    expect(writes[refusingSpaceId], 1);
    expect(writes[acceptingSpaceId], analyticsRoomIds.length);
    expect(counter.events, 1);
  });
}
