import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #9666 — the open chat rides the workspace URL as a `room:` panel token, not
/// a path segment. An `activeRoomId` that read only the path was always null,
/// so every message in the chat the learner had open raised a notification
/// (and, on web, a sound) for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? activeRoomIdAt(String location) {
    FluffyChatApp.router.go(location);
    return MatrixState().activeRoomId;
  }

  test('the open chat is the active room', () {
    expect(
      activeRoomIdAt('/?left=chats,room:!abc:server.org'),
      '!abc:server.org',
    );
  });

  test('no open chat means no active room', () {
    expect(activeRoomIdAt('/?left=chats'), isNull);
  });
}
