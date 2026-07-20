import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

/// Star display math (quests.instructions.md, "Star display on the course
/// panel"): per-Mission display shows raw stars over the threshold (surplus
/// shows, e.g. 12/7), while the quest header sums each Mission's stars CAPPED
/// at its threshold — one over-practiced Mission can't inflate quest progress
/// — over the summed thresholds.
void main() {
  group('MissionProgress.cappedStars', () {
    test('below threshold passes through', () {
      expect(const MissionProgress(stars: 4, threshold: 7).cappedStars, 4);
    });

    test('overflow caps at the threshold', () {
      expect(const MissionProgress(stars: 12, threshold: 7).cappedStars, 7);
    });
  });

  group('ProgressionResolution.questStars', () {
    // Rollups hang off the quest they were resolved for, so the summary reads
    // one course's own numbers rather than a cross-course blend (#7771).
    ProgressionResolution resolutionWith(Map<String, MissionProgress> rollup) =>
        ProgressionResolution(
          quests: [
            QuestProgress(
              courseId: 'c1',
              orderedMissionIds: rollup.keys.toList(),
              anchorMissionId: null,
              indexByMission: const {},
              rollup: rollup,
            ),
          ],
        );

    test('sums capped stars over summed thresholds (mockup: 4+1 → ⭐5)', () {
      final resolution = resolutionWith({
        'getting-around': const MissionProgress(stars: 4, threshold: 7),
        'introductions': const MissionProgress(stars: 1, threshold: 7),
      });
      final summary = resolution.questStars('c1', [
        'getting-around',
        'introductions',
      ]);
      expect(summary.earned, 5);
      expect(summary.total, 14);
      expect(summary.fraction, closeTo(5 / 14, 1e-9));
    });

    test('an over-practiced Mission contributes at most its threshold', () {
      final resolution = resolutionWith({
        'a': const MissionProgress(stars: 12, threshold: 7),
        'b': const MissionProgress(stars: 0, threshold: 7),
      });
      final summary = resolution.questStars('c1', ['a', 'b']);
      expect(summary.earned, 7);
      expect(summary.total, 14);
    });

    test('a Mission missing from the rollup keeps a stable denominator '
        '(default threshold, zero stars)', () {
      final resolution = resolutionWith({
        'known': const MissionProgress(stars: 3, threshold: 7),
      });
      final summary = resolution.questStars('c1', ['known', 'unknown']);
      expect(summary.earned, 3);
      expect(summary.total, 7 + kDefaultStarsToUnlockObjective);
    });

    test('empty quest yields zero with a safe fraction', () {
      final summary = resolutionWith({}).questStars('c1', const []);
      expect(summary.earned, 0);
      expect(summary.total, 0);
      expect(summary.fraction, 0);
    });
  });
}
