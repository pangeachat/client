import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'get_test_client.dart';

/// Finishing an activity with the network down left the summary spinner
/// running forever (#8362): the error state is signalled through a room-state
/// write, which needs exactly the network that just failed. The fix applies
/// the state locally and announces it on `onRoomState` when the server write
/// throws — the chat's StreamBuilder rebuilds and shows error + retry.
///
/// `FakeMatrixApi` has no handlers for this room, so every call
/// `fetchSummaries` makes (state PUTs, /messages) fails — the whole flow runs
/// as if offline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = '!offline:fakeServer.notExisting';
  const langCode = 'en';

  late Client client;

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() => client.dispose());

  test('an offline summary fetch lands the error state locally', () async {
    final room = Room(id: roomId, client: client, membership: Membership.join);

    // Both fallbacks announce: first the requestedAt state, then the errorAt
    // state. The announcement is what rebuilds the chat view's StreamBuilder.
    final announcedError = client.onRoomState.stream
        .where(
          (update) =>
              update.roomId == roomId &&
              update.state.type == PangeaEventTypes.activitySummary &&
              update.state.content['error_at'] != null,
        )
        .first;

    await room.fetchSummaries(langCode);

    final state = room.getState(PangeaEventTypes.activitySummary, langCode);
    expect(state, isNotNull, reason: 'state must land locally when offline');

    final summary = ActivitySummaryModel.fromJson(
      Map<String, dynamic>.from(state!.content),
    );
    expect(summary.hasError, isTrue);
    expect(summary.isLoading, isFalse, reason: 'the spinner must stop');

    await expectLater(
      announcedError.timeout(const Duration(seconds: 1)),
      completes,
    );
  });
}
