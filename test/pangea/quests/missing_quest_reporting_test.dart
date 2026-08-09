import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/world/world_map_pins_manager.dart';

/// CLIENT-DQC (#8094): a missing quest is a state the repo classified benign —
/// [QuestRepo.quest] returns [MissingQuestException] without reporting, and the
/// course panel renders it as a known state — yet the world map's objective
/// cache rebuild reported it to Sentry at `error`, titled `Instance of
/// 'MissingQuestException'`. These pin both halves of the fix: a real
/// `toString()`, and the caller keeping the repo's classification (warning,
/// not error) while other outline failures stay errors.
void main() {
  test('MissingQuestException has a diagnosable toString', () {
    expect(
      MissingQuestException().toString(),
      'MissingQuestException: quest plan not found in CMS (confirmed 404)',
    );
  });

  group('courseOutlineErrorLevel', () {
    test('a missing quest reports at warning — repo classified it benign', () {
      expect(
        courseOutlineErrorLevel(MissingQuestException()),
        SentryLevel.warning,
      );
    });

    test('any other outline failure stays an error', () {
      expect(
        courseOutlineErrorLevel(Exception('choreo unreachable')),
        SentryLevel.error,
      );
    });
  });
}
