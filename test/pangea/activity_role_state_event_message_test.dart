import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/l10n/l10n_en.dart';

/// Which activity-role state transitions get a timeline row (#8288): the
/// transition into finished, and the rejoin transition back out of it
/// ("Wait, I'm not done!"). Everything else — a fresh role claim, the
/// auto-save's archived_at re-write — stays silent.
void main() {
  final l10n = L10nEn();

  ActivityRoleModel role({DateTime? finishedAt, DateTime? archivedAt}) =>
      ActivityRoleModel(
        id: 'role-1',
        userId: '@user:server',
        role: 'Detective',
        finishedAt: finishedAt,
        archivedAt: archivedAt,
      );

  final now = DateTime.now();

  test('finishing gets a row', () {
    expect(
      role(finishedAt: now).stateEventMessage('User', l10n, previous: role()),
      l10n.finishedTheActivity('User'),
    );
  });

  test('rejoining after finishing gets a row', () {
    expect(
      role().stateEventMessage('User', l10n, previous: role(finishedAt: now)),
      l10n.rejoinedTheActivity('User'),
    );
  });

  test('a fresh role claim (no previous entry) stays silent', () {
    expect(role().stateEventMessage('User', l10n), isNull);
  });

  test('a discussion seat ended by the server, finished and archived in one '
      'write, gets a row (#9647)', () {
    expect(
      role(
        finishedAt: now,
        archivedAt: now,
      ).stateEventMessage('User', l10n, previous: role()),
      l10n.finishedTheActivity('User'),
    );
  });

  test('a discussion seat reopened by the server, both cleared at once, '
      'gets the rejoin row (#9647)', () {
    expect(
      role().stateEventMessage(
        'User',
        l10n,
        previous: role(finishedAt: now, archivedAt: now),
      ),
      l10n.rejoinedTheActivity('User'),
    );
  });

  test('the auto-save archived_at re-write stays silent', () {
    expect(
      role(
        finishedAt: now,
        archivedAt: now,
      ).stateEventMessage('User', l10n, previous: role(finishedAt: now)),
      isNull,
    );
  });
}
