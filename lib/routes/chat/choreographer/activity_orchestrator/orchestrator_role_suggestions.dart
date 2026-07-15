import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';

class OrchestratorRoleSuggestions {
  final String roleId;
  final List<OrchestratorSuggestion> suggestions;

  const OrchestratorRoleSuggestions({
    required this.roleId,
    required this.suggestions,
  });

  static OrchestratorRoleSuggestions fromJson(Map<String, dynamic> json) {
    // v2 (choreo#2761): options may be empty (adapted Reaction / turn-0 null
    // buckets) or malformed during rollout — skip bad entries, never throw.
    return OrchestratorRoleSuggestions(
      roleId: json["role_id"],
      suggestions: List.from(json["suggestions"] ?? [])
          .whereType<Map>()
          .where(
            (s) =>
                s["text"] is String &&
                OrchestratorSuggestionType.values.any(
                  (v) => v.name == s["type"],
                ),
          )
          .map(
            (s) =>
                OrchestratorSuggestion.fromJson(Map<String, dynamic>.from(s)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    "role_id": roleId,
    "suggestions": suggestions.map((s) => s.toJson()).toList(),
  };
}
