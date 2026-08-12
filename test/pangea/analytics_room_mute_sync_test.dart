import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/pangea_push_rules_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';

/// Analytics rooms that appear mid-session (auto-granted instructor access,
/// force-joins) must be detected in sync so their dontNotify rule is set
/// without waiting for the next app start (#8267).
void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  MatrixEvent createEvent(String? roomType) => MatrixEvent(
    type: EventTypes.RoomCreate,
    content: {'type': ?roomType},
    senderId: '@student:fakeServer.notExisting',
    stateKey: '',
    eventId: '\$create',
    originServerTs: DateTime.utc(2026, 1, 1),
  );

  SyncUpdate sync({RoomsUpdate? rooms}) =>
      SyncUpdate(nextBatch: 'batch', rooms: rooms);

  test('matches a newly joined analytics room', () {
    final update = sync(
      rooms: RoomsUpdate(
        join: {
          '!analytics:server': JoinedRoomUpdate(
            state: [createEvent(PangeaRoomTypes.analytics)],
          ),
        },
      ),
    );
    expect(client.isNewAnalyticsRoomSyncUpdate(update), isTrue);
  });

  test('matches an analytics room invite via stripped state', () {
    final update = sync(
      rooms: RoomsUpdate(
        invite: {
          '!analytics:server': InvitedRoomUpdate(
            inviteState: [
              StrippedStateEvent(
                type: EventTypes.RoomCreate,
                content: {'type': PangeaRoomTypes.analytics},
                senderId: '@student:fakeServer.notExisting',
                stateKey: '',
              ),
            ],
          ),
        },
      ),
    );
    expect(client.isNewAnalyticsRoomSyncUpdate(update), isTrue);
  });

  test('ignores ordinary rooms, spaces and empty updates', () {
    expect(client.isNewAnalyticsRoomSyncUpdate(sync()), isFalse);
    expect(
      client.isNewAnalyticsRoomSyncUpdate(
        sync(
          rooms: RoomsUpdate(
            join: {
              '!chat:server': JoinedRoomUpdate(state: [createEvent(null)]),
              '!space:server': JoinedRoomUpdate(
                state: [createEvent('m.space')],
              ),
            },
          ),
        ),
      ),
      isFalse,
    );
  });

  test('ignores non-create analytics-typed events', () {
    final update = sync(
      rooms: RoomsUpdate(
        join: {
          '!chat:server': JoinedRoomUpdate(
            state: [
              MatrixEvent(
                type: EventTypes.RoomMember,
                content: {'type': PangeaRoomTypes.analytics},
                senderId: '@student:fakeServer.notExisting',
                stateKey: '@teacher:fakeServer.notExisting',
                eventId: '\$member',
                originServerTs: DateTime.utc(2026, 1, 1),
              ),
            ],
          ),
        },
      ),
    );
    expect(client.isNewAnalyticsRoomSyncUpdate(update), isFalse);
  });
}
