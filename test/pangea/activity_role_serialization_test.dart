import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';

/// The choreographer's Role schema defaults a missing legacy `goal` but 422s
/// on an explicit null (Pydantic string_type). v2 roles carry the `goals`
/// pool and no legacy goal string, so serializing `'goal': null` broke every
/// v2 activity-summary request. The key must be omitted when null.
void main() {
  group('ActivityRole.toJson', () {
    test('omits the legacy goal key when null (v2 role with goals pool)', () {
      final role = ActivityRole(
        id: 'estudiante_a',
        name: 'Estudiante A',
        goal: null,
        goals: [ActivityRoleGoal(id: 'g1', description: 'Describe a person')],
      );
      expect(role.toJson().containsKey('goal'), isFalse);
    });

    test('keeps the legacy goal string when set (v1 role)', () {
      final role = ActivityRole(
        id: 'estudiante_a',
        name: 'Estudiante A',
        goal: 'Describe a person',
        goals: const [],
      );
      expect(role.toJson()['goal'], 'Describe a person');
    });
  });
}
