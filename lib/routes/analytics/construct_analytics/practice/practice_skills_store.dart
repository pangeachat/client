import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';

/// The exercise types a learner keeps on for vocab practice, chosen on the
/// start page and kept on this device. Logging out erases the box (it is in
/// PangeaController's storage keys), so the next account starts with every
/// type on. See practice-exercises.instructions.md, "Start page".
class PracticeSkillsStore {
  static const String storageKey = 'practice_skills_storage';
  static const String _vocabSkillsKey = 'vocab_skills';

  /// What a vocab session can practice: meaning exercises (reading),
  /// listening, and read-aloud (speaking).
  static const Set<LearningSkillsEnum> vocabSkills = {
    LearningSkillsEnum.reading,
    LearningSkillsEnum.hearing,
    LearningSkillsEnum.speaking,
  };

  static GetStorage get _storage => GetStorage(storageKey);

  /// The learner's last choice, or every type when they have never chosen.
  static Future<Set<LearningSkillsEnum>> load() async {
    await GetStorage.init(storageKey);
    final stored = _storage.read(_vocabSkillsKey);
    if (stored == null) return vocabSkills;
    if (stored is! List) {
      ErrorHandler.logError(
        e: 'Unexpected stored practice skills',
        data: {'stored': stored.toString()},
      );
      return vocabSkills;
    }
    final skills = vocabSkills.where((s) => stored.contains(s.name)).toSet();
    return skills.isEmpty ? vocabSkills : skills;
  }

  /// A failed write is reported and the session still uses [skills]; only
  /// the next session forgets them.
  static Future<void> save(Set<LearningSkillsEnum> skills) async {
    try {
      await GetStorage.init(storageKey);
      await _storage.write(_vocabSkillsKey, [for (final s in skills) s.name]);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'skills': skills.toString()});
    }
  }
}
