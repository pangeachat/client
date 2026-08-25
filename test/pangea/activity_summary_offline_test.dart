import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'get_test_client.dart';

/// Finishing an activity with the network down left the summary spinner
/// running forever (#8362): the error status is signalled through a
/// room-state write, which needs exactly the network that just failed, and
/// the failure escaped `fetchSummaries` without any signal to the UI. The fix
/// makes `fetchSummaries` swallow nothing: it must complete (not throw) and
/// report failure through its return value, which ActivityChatController
/// turns into local error UI.
///
/// `FakeMatrixApi` has no handlers for this room, so every call the flow
/// makes (state PUTs, /messages) fails — the whole flow runs as if offline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = '!offline:fakeServer.notExisting';

  late Client client;

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() => client.dispose());

  test('an offline summary fetch completes and reports failure', () async {
    final room = Room(id: roomId, client: client, membership: Membership.join);

    // Must not throw — even recording the error state needs the network, and
    // that throw is what used to escape and strand the spinner.
    final ok = await room.fetchSummaries('en');

    expect(ok, isFalse);
  });
}
