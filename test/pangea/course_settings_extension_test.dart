import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'get_test_client.dart';

/// #9589 — changing "Require analytics access" rewrote `pangea.course_settings`
/// from a model that knows only that one key, so every other key on the event
/// was dropped. A central course's `central` mark lives on the same event
/// (central-courses.instructions.md), and toggling the setting erased it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const courseRoomId = '!course:fakeServer.notExisting';

  late Client client;
  late List<Map<String, dynamic>> written;

  setUp(() async {
    client = await getTestClient();
    written = [];
    FakeMatrixApi
            .currentApi!
            .api['PUT']!['/client/v3/rooms/${Uri.encodeComponent(courseRoomId)}/state/${PangeaEventTypes.courseSettings}'] =
        (body) {
          written.add(jsonDecode(body as String) as Map<String, dynamic>);
          return {'event_id': '\$settings'};
        };
  });

  tearDown(() async {
    await client.dispose();
  });

  Room courseRoom(Map<String, dynamic>? settings) {
    final room = Room(
      id: courseRoomId,
      client: client,
      membership: Membership.join,
    );
    if (settings != null) {
      room.setState(
        Event(
          type: PangeaEventTypes.courseSettings,
          content: settings,
          senderId: userId,
          eventId: '\$settings0',
          originServerTs: DateTime.utc(2026, 1, 1),
          stateKey: '',
          room: room,
        ),
      );
    }
    return room;
  }

  /// The content of the one settings write [change] makes. The save then
  /// waits for the room's next sync, which the fake never sends, so the
  /// future is left running.
  Future<Map<String, dynamic>> contentWritten(
    Future<void> Function() change,
  ) async {
    unawaited(change());
    for (var i = 0; i < 50 && written.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(written, hasLength(1));
    return written.single;
  }

  test('turning the setting on keeps the central mark', () async {
    final room = courseRoom({
      'require_analytics_access': false,
      'central': true,
    });
    expect(await contentWritten(() => room.setRequireAnalyticsAccess(true)), {
      'require_analytics_access': true,
      'central': true,
    });
  });

  test('toggling keeps every key the client does not know', () async {
    final room = courseRoom({
      'require_analytics_access': true,
      'central': true,
      'added_later': {'any': 'shape'},
    });
    expect(await contentWritten(room.toggleRequireAnalyticsAccess), {
      'require_analytics_access': false,
      'central': true,
      'added_later': {'any': 'shape'},
    });
  });

  test('a course without settings writes only the setting', () async {
    final room = courseRoom(null);
    expect(await contentWritten(() => room.setRequireAnalyticsAccess(true)), {
      'require_analytics_access': true,
    });
  });
}
