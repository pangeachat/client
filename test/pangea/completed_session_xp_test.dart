import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'activity_session_fixtures.dart';
import 'get_test_client.dart';

/// What one finished session paid the learner, as the start page's
/// completed-sessions subpage shows it beside each session
/// (activity-start-page.instructions.md, "Completed sessions"): the XP
/// credited to the session's room plus a flat goal XP per goal awarded to the
/// learner's own role there.
void main() {
  late Client client;

  const otherId = '@other:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room session({Map<String, List<String>> awarded = const {}}) =>
      activitySessionRoom(
        client,
        roles: {
          'r1': ActivityRoleModel(
            id: 'r1',
            userId: testSessionUserId,
            role: 'Fan',
          ),
          'r2': ActivityRoleModel(id: 'r2', userId: otherId, role: 'Visitor'),
        },
        awarded: awarded,
      );

  test('credited room XP plus goal XP for each of the learner own goals', () {
    final room = session(
      awarded: {
        'r1': ['slug-1', 'slug-2'],
        // The partner's goals paid the partner, not the learner.
        'r2': ['slug-4'],
      },
    );
    expect(client.sessionXp(room, {room.id: 30}), 30 + 2 * kGoalXp);
  });

  test('a session with nothing credited pays only its goals', () {
    final room = session(
      awarded: {
        'r1': ['slug-1'],
      },
    );
    expect(client.sessionXp(room, const {}), kGoalXp);
  });

  test('a session that paid nothing reads as zero', () {
    expect(client.sessionXp(session(), const {}), 0);
  });
}
