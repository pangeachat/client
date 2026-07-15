import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';

class OrchestratorRoleSuggestions {
  final String roleId;
  final List<OrchestratorSuggestion> suggestions;

  const OrchestratorRoleSuggestions({
    required this.roleId,
    required this.suggestions,
  });

  static OrchestratorRoleSuggestions fromJson(Map<String, dynamic> json) {
    // Under the v2 contract (choreo#2761) a bucket's options list may be
    // empty (the bot adapts Reaction and turn-0 null buckets to empty lists)
    // and unknown option shapes may appear during rollout. Skip malformed
    // entries instead of throwing — one bad entry must not discard the
    // whole orchestrator output.
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
