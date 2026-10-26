import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

/// Star display math (quests.instructions.md, "Star display on the course
/// panel"): a star is a completed Mission, so the quest header counts
/// completed Missions over the Missions that can be completed. Per-Mission
/// display shows raw XP over the threshold (surplus shows, e.g. 340/300); a
/// Mission over-practised past its threshold is still one star (#9420).
void main() {
  group('ProgressionResolution.questStars', () {
    // Rollups hang off the quest they were resolved for, so the summary reads
    // one course's own numbers rather than a cross-course blend (#7771).
    ProgressionResolution resolutionWith(Map<String, MissionProgress> rollup) =>
        ProgressionResolution(
          quests: [
            QuestProgress(
              courseId: 'c1',
              questId: 'c1',
              orderedMissionIds: rollup.keys.toList(),
              anchorMissionId: null,
              indexByMission: const {},
              rollup: rollup,
            ),
          ],
        );

    test('counts completed Missions over scored Missions', () {
      final resolution = resolutionWith({
        'getting-around': const MissionProgress(xp: 300, threshold: 300),
        'introductions': const MissionProgress(xp: 100, threshold: 300),
      });
      final summary = resolution.questStars('c1')!;
      expect(summary.earned, 1);
      expect(summary.total, 2);
      expect(summary.fraction, closeTo(1 / 2, 1e-9));
    });

    test('an over-practised Mission is one star, not more', () {
      final resolution = resolutionWith({
        'a': const MissionProgress(xp: 900, threshold: 300),
        'b': const MissionProgress(xp: 0, threshold: 300),
      });
      final summary = resolution.questStars('c1')!;
      expect(summary.earned, 1);
      expect(summary.total, 2);
    });

    test('a Mission outside the rollup adds nothing to the denominator', () {
      // #7663: the rollup holds only Missions with activities. An activity-less
      // Mission is hidden from the panel and cannot be completed, so it must
      // not count — the summary counts what the rollup holds and nothing else.
      final resolution = resolutionWith({
        'known': const MissionProgress(xp: 120, threshold: 300),
      });
      final summary = resolution.questStars('c1')!;
      expect(summary.earned, 0);
      expect(summary.total, 1);
    });

    test('empty quest yields zero with a safe fraction', () {
      final summary = resolutionWith({}).questStars('c1')!;
      expect(summary.earned, 0);
      expect(summary.total, 0);
      expect(summary.fraction, 0);
    });

    test('an unresolved course is null, not an invented denominator', () {
      // The header renders its muted empty bar on null (ProgressBarRow).
      expect(ProgressionResolution.empty.questStars('c1'), isNull);
      expect(resolutionWith({}).questStars('other-course'), isNull);
      expect(resolutionWith({}).questStars(null), isNull);
    });
  });
}
