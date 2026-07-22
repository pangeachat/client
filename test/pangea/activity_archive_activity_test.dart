import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'get_test_client.dart';

/// archiveActivity must hand its caller the canonical archived-at it persists,
/// so the dosage session-outcome emit does not race `/sync`. Reading
/// ownRoleState.archivedAt right after the write can see null (the archive
/// hasn't synced back into local state), which used to make the emit skip
/// permanently once the auto-save gate closed on the archived role.
///
/// The room id is FakeMatrixApi's magic `!1234:...`, the only room whose state
/// PUTs the fake homeserver accepts.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const roomId = '!1234:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Room roomWithRole(ActivityRoleModel role) {
    final room = Room(id: roomId, client: client);
    room.setState(
      Event(
        type: PangeaEventTypes.activityRole,
        content: ActivityRolesModel({role.id: role}).toJson(),
        senderId: userId,
        eventId: '\$role',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: room,
      ),
    );
    return room;
  }

  ActivityRoleModel finishedRole({DateTime? archivedAt}) => ActivityRoleModel(
    id: 'role-1',
    userId: userId,
    role: 'Interviewer',
    finishedAt: DateTime.utc(2026, 1, 1, 12),
    archivedAt: archivedAt,
  );

  Map<String, dynamic>? lastRolePutBody() {
    final entry = FakeMatrixApi.calledEndpoints.entries.where(
      (e) => e.key.contains('/state/${PangeaEventTypes.activityRole}'),
    );
    if (entry.isEmpty) return null;
    final recorded = entry.first.value.last;
    return Map<String, dynamic>.from(
      recorded is String ? jsonDecode(recorded) as Map : recorded as Map,
    );
  }

  test(
    'returns the canonical archived-at it persists (not a racy state re-read)',
    () async {
      final room = roomWithRole(finishedRole());
      expect(
        room.ownRoleState?.archivedAt,
        isNull,
        reason: 'precondition: not archived yet',
      );
      FakeMatrixApi.calledEndpoints.clear();

      final returned = await room.archiveActivity();

      expect(
        returned,
        isNotNull,
        reason: 'the caller gets the archived-at directly, without a sync',
      );
      // It is EXACTLY the value written to room state, so the server verifies
      // the same completed_at the client reports.
      final body = lastRolePutBody();
      expect(body, isNotNull, reason: 'the archive was persisted');
      final persisted =
          ((body!['roles'] as Map)['role-1'] as Map)['archived_at'];
      expect(persisted, returned!.toIso8601String());
    },
  );

  test(
    'an already-archived role returns its existing archived-at, no re-write',
    () async {
      final archivedAt = DateTime.utc(2026, 1, 1, 12, 30);
      final room = roomWithRole(finishedRole(archivedAt: archivedAt));
      FakeMatrixApi.calledEndpoints.clear();

      final returned = await room.archiveActivity();

      expect(returned, archivedAt, reason: 'the canonical value, unchanged');
      expect(
        lastRolePutBody(),
        isNull,
        reason: 'no state PUT: the role is already archived',
      );
    },
  );

  test('returns null when there is no finished role to archive', () async {
    final room = roomWithRole(
      ActivityRoleModel(id: 'role-1', userId: userId, role: 'Interviewer'),
    );
    expect(await room.archiveActivity(), isNull);
  });
}
