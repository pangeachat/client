/// A v3 Learning Objective (learner-facing: "Mission"), read from the CMS
/// `learning-objectives` collection.
///
/// Objectives are language-neutral can-do statements, so the text is canonical
/// (not localized per viewer). Tolerant of the collection's in-progress
/// req/res migration: prefers `res.objective` but falls back to the legacy
/// flat `objective` field.
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
}
