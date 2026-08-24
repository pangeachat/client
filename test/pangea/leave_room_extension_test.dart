import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/extensions/leave_room_extension.dart';
import 'get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = '!archived:fakeServer.notExisting';
  const leavePath = '/client/v3/rooms/!archived%3AfakeServer.notExisting/leave';

  late Client client;
  late FakeMatrixApi api;

  setUp(() async {
    client = await getTestClient();
    api = FakeMatrixApi.currentApi!;
  });

  tearDown(() async {
    await client.dispose();
  });

  Room joinedRoom() =>
      Room(id: roomId, client: client, membership: Membership.join);

  group('leaveIgnoringUnknownRoom', () {
    test('completes when the homeserver does not know the room', () async {
      api.api['POST']![leavePath] = (_) => {
        'errcode': 'M_UNKNOWN',
        'error': 'Not a known room',
      };

      await expectLater(joinedRoom().leaveIgnoringUnknownRoom(), completes);
    });

    test('completes when the homeserver cannot find the room', () async {
      api.api['POST']![leavePath] = (_) => {
        'errcode': 'M_NOT_FOUND',
        'error': 'Room not found',
      };

      await expectLater(joinedRoom().leaveIgnoringUnknownRoom(), completes);
    });

    test('rethrows a leave the homeserver refused', () async {
      api.api['POST']![leavePath] = (_) => {
        'errcode': 'M_FORBIDDEN',
        'error': 'You are not allowed to leave this room',
      };

      await expectLater(
        joinedRoom().leaveIgnoringUnknownRoom(),
        throwsA(
          isA<MatrixException>().having(
            (e) => e.error,
            'error',
            MatrixError.M_FORBIDDEN,
          ),
        ),
      );
    });

    test('leaves a room the homeserver does know', () async {
      var left = false;
      api.api['POST']![leavePath] = (_) {
        left = true;
        return <String, Object?>{};
      };

      await joinedRoom().leaveIgnoringUnknownRoom();
      expect(left, isTrue);
    });
  });
}
