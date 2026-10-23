import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

/// What a finished practice session's XP did, read back from the learner's
/// analytics by the rules the Mission meters read it by, rather than summed
/// from the answers: XP past a word's flower cap counts nowhere, and a
/// read-aloud item pays words outside the Mission's list (#9633).
class PracticeSessionXp {
  /// XP the session's uses earned within each word's flower cap.
  final int counted;

  /// How far the Mission's practice share moved. Null outside Objective
  /// practice.
  final int? missionGain;

  const PracticeSessionXp._({required this.counted, this.missionGain});

  /// [sessionUses] are the uses the session recorded; [learnerUses] the
  /// learner's uses in its language as `AnalyticsDataService.getUses` returns
  /// them, cap-filtered and including the session's. [missionLemmas] is the
  /// Mission's credited word list, for Objective practice.
  factory PracticeSessionXp.measure({
    required Iterable<OneConstructUse> sessionUses,
    required Iterable<OneConstructUse> learnerUses,
    Set<String>? missionLemmas,
  }) {
    // Matched by what a use is and when, to the millisecond the store keeps.
    // An answer's accuracy and speed bonuses can share all of that, so
    // matches are counted rather than looked up.
    final unmatched = <String, int>{};
    for (final use in sessionUses) {
      unmatched.update(_key(use), (n) => n + 1, ifAbsent: () => 1);
    }
    var counted = 0;
    final others = <OneConstructUse>[];
    for (final use in learnerUses) {
      final key = _key(use);
      final left = unmatched[key] ?? 0;
      if (left == 0) {
        others.add(use);
        continue;
      }
      unmatched[key] = left - 1;
      counted += use.xp;
    }
    if (missionLemmas == null) return PracticeSessionXp._(counted: counted);

    int missionPractice(Iterable<OneConstructUse> uses) =>
        MissionXpBreakdown.practiceFor(
          missionLemmas,
          MissionXpCache.practiceXpByLemmaOf(uses),
        );
    return PracticeSessionXp._(
      counted: counted,
      missionGain: missionPractice(learnerUses) - missionPractice(others),
    );
  }

  static String _key(OneConstructUse use) =>
      '${use.identifier.string}|${use.useType.name}|'
      '${use.timeStamp.millisecondsSinceEpoch}';
}
