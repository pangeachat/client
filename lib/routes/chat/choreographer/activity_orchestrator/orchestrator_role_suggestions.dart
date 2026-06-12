import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';

class OrchestratorRoleSuggestions {
  final String roleId;
  final List<OrchestratorSuggestion> suggestions;

  const OrchestratorRoleSuggestions({
    required this.roleId,
    required this.suggestions,
  });

  static OrchestratorRoleSuggestions fromJson(Map<String, dynamic> json) {
    return OrchestratorRoleSuggestions(
      roleId: json["role_id"],
      suggestions: List.from(json["suggestions"])
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
