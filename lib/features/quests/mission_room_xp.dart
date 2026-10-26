import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';

/// The learner's in-room XP by room, one map per part of a session — chat,
/// speaking and practice — plus the skills of the parts that count. Read by
/// the Mission XP cache (quests.instructions.md, "What fills a Mission").
class MissionRoomXp {
  final Map<String, int> chat = {};
  final Map<String, int> speaking = {};
  final Map<String, int> practice = {};
  final Map<String, Map<LearningSkillsEnum, int>> skills = {};

  /// [uses]' in-room XP, each part kept only where it nets above zero in a
  /// room: wrong answers in one part never take XP earned in another, and no
  /// Mission shows a negative share. Only the parts that count keep their
  /// skills, so a Mission's skill tiles still sum to its split. [uses] are
  /// cap-filtered, as `AnalyticsDataService.getUses` returns them.
  MissionRoomXp.of(Iterable<OneConstructUse> uses) {
    final inRoom = [
      for (final use in uses)
        if (use.xp != 0 && use.metadata.roomId != null) use,
    ];
    for (final use in inRoom) {
      final part = partOf(use);
      final roomId = use.metadata.roomId!;
      part[roomId] = (part[roomId] ?? 0) + use.xp;
    }
    for (final part in [chat, speaking, practice]) {
      part.removeWhere((_, xp) => xp <= 0);
    }
    for (final use in inRoom) {
      final roomId = use.metadata.roomId!;
      if (partOf(use).containsKey(roomId)) addSkill(skills, roomId, use);
    }
  }

  /// The part [use] counts toward.
  Map<String, int> partOf(OneConstructUse use) => use.useType.isChatUse
      ? chat
      : use.useType.skillsEnumType == LearningSkillsEnum.speaking
      ? speaking
      : practice;

  /// Adds [use]'s XP to its skill under [key] in [into].
  static void addSkill(
    Map<String, Map<LearningSkillsEnum, int>> into,
    String key,
    OneConstructUse use,
  ) {
    final skills = into[key] ??= {};
    final skill = use.useType.skillsEnumType;
    skills[skill] = (skills[skill] ?? 0) + use.xp;
  }
}
