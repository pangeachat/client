/// A v3 Learning Objective (learner-facing: "Mission").
///
/// The statement is read in the learner's resolved display language from
/// choreo's course outline read ([fromOutlineJson]); the course outline is a
/// Mission's full tier, so the server translates on a miss (org
/// quests-and-learning-objectives doc § Content access and localization,
/// #8577). [fromJson] parses a raw CMS `learning-objectives` row — canonical
/// text — for the places a quest row still embeds one at depth ≥ 1.
class LearningObjective {
  final String id;
  final String objective;
  final String? theme;
  final String? cefr;

  const LearningObjective({
    required this.id,
    required this.objective,
    this.theme,
    this.cefr,
  });

  factory LearningObjective.fromJson(Map<String, dynamic> json) {
    final res = (json['res'] as Map?)?.cast<String, dynamic>() ?? const {};
    final req = (json['req'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LearningObjective(
      id: json['id'] as String,
      objective: (res['objective'] ?? json['objective'] ?? '') as String,
      theme: (res['theme'] ?? req['theme'] ?? json['theme']) as String?,
      cefr: (req['cefr_level'] ?? json['cefr_level']) as String?,
    );
  }

  /// One entry of the outline read's `missions`:
  /// `{lo_id, objective, source_l1, localized, theme, cefr_level, scale_id}`.
  /// Null when the entry carries no id or no statement — a malformed entry is
  /// dropped rather than rendered as a blank Mission header.
  static LearningObjective? fromOutlineJson(Map<String, dynamic> json) {
    final id = json['lo_id'];
    final objective = json['objective'];
    if (id is! String || id.isEmpty || objective is! String) return null;
    return LearningObjective(
      id: id,
      objective: objective,
      theme: json['theme'] as String?,
      cefr: json['cefr_level'] as String?,
    );
  }
}
