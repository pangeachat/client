import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';
import 'sentry_capture_harness.dart';

/// A learner's analytics rooms are added to every course space they are in.
///
/// A space the server refuses (`M_FORBIDDEN`) refuses every room for the same
/// reason, so the first refusal ends the work on that space: one request and
/// one report, not one of each per analytics room (#9181).
///
/// The writes share the learner's per-user event budget on the homeserver, so
/// the pass rests after each batch of rooms, and a write the server
/// rate-limits anyway (`M_LIMIT_EXCEEDED`) is a warning followed by a rest,
/// not an error followed by the next write (#9203).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const firstSpaceId = '!first:fakeServer.notExisting';
  const secondSpaceId = '!second:fakeServer.notExisting';
  const analyticsRoomIds = [
    '!analyticsEs:fakeServer.notExisting',
    '!analyticsFr:fakeServer.notExisting',
    '!analyticsDe:fakeServer.notExisting',
  ];

  final counter = SentryEventCounter();
  late Client client;
  late FakeMatrixApi api;
  late Map<String, int> writes;
  late Map<String, List<DateTime>> writeTimes;

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

  /// Answers the nth space-child write to [spaceId] with [response], counting
  /// and timing them. The matching parent write on the analytics room, which
  /// the SDK makes after a child write succeeds, is always accepted.
  void stubSpace(
    String spaceId,
    Map<String, dynamic> Function(int nth) response,
  ) {
    for (final childId in analyticsRoomIds) {
      api.api['PUT']![stateAction(
        spaceId,
        EventTypes.SpaceChild,
        childId,
      )] = (_) {
        final nth = writes[spaceId] ?? 0;
        writes[spaceId] = nth + 1;
        (writeTimes[spaceId] ??= []).add(DateTime.now());
        return response(nth);
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
    writeTimes = {};
    // The spaces are visited in this order, so the second one is only reached
    // if whatever happens in the first leaves the rest of the pass alone.
    joinedRoom(firstSpaceId, RoomCreationTypes.mSpace);
    joinedRoom(secondSpaceId, RoomCreationTypes.mSpace);
    for (final roomId in analyticsRoomIds) {
      joinedRoom(roomId, PangeaRoomTypes.analytics);
    }
  });

  tearDown(() async {
    await client.dispose();
    await counter.close();
  });

  Map<String, dynamic> accepted(int _) => {'event_id': '\$child'};

  /// Waits until [spaceId] has seen [count] child writes. The pass is never
  /// awaited: it rests for up to ten seconds after each space it wrote to.
  Future<void> untilWrites(String spaceId, int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while ((writes[spaceId] ?? 0) < count &&
        DateTime.now().isBefore(deadline)) {
      await pumpEventQueue();
    }
  }

  test('a refused space costs one write and one report', () async {
    stubSpace(
      firstSpaceId,
      (_) => {
        'errcode': 'M_FORBIDDEN',
        'error': 'User $userId not in room $firstSpaceId',
      },
    );
    stubSpace(secondSpaceId, accepted);

    unawaited(client.addAnalyticsRoomsToSpaces());
    await untilWrites(secondSpaceId, analyticsRoomIds.length);

    expect(writes[firstSpaceId], 1);
    expect(writes[secondSpaceId], analyticsRoomIds.length);
    expect(counter.events, 1);
  });

  test('the pass rests after each batch of rooms', () async {
    const rest = Duration(milliseconds: 500);
    stubSpace(firstSpaceId, accepted);
    stubSpace(secondSpaceId, accepted);

    unawaited(client.addAnalyticsRoomsToSpaces(batchRooms: 2, batchRest: rest));
    await untilWrites(firstSpaceId, 2);
    // The batch is full: nothing more is written until the rest is over.
    await Future.delayed(const Duration(milliseconds: 150));
    expect(writes[firstSpaceId], 2);

    await untilWrites(firstSpaceId, analyticsRoomIds.length);
    final times = writeTimes[firstSpaceId]!;
    expect(times[2].difference(times[1]), greaterThanOrEqualTo(rest));
    expect(counter.events, 0);
  });

  test(
    'a rate-limited write is a warning and a rest, and the pass goes on',
    () async {
      const rest = Duration(milliseconds: 300);
      // The first write the server sees is the one it rate-limits, asking for
      // less than a batch rest; the room is left for the next pass.
      stubSpace(
        firstSpaceId,
        (nth) => nth == 0
            ? {
                'errcode': 'M_LIMIT_EXCEEDED',
                'error': 'Too Many Requests',
                'retry_after_ms': 100,
              }
            : accepted(nth),
      );
      stubSpace(secondSpaceId, accepted);

      unawaited(client.addAnalyticsRoomsToSpaces(batchRest: rest));
      await untilWrites(firstSpaceId, analyticsRoomIds.length);

      final times = writeTimes[firstSpaceId]!;
      expect(times[1].difference(times[0]), greaterThanOrEqualTo(rest));
      expect(counter.events, 1);
      expect(counter.levels, [SentryLevel.warning]);
    },
  );
}
