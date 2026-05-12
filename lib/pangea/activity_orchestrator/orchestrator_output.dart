import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_flag.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_role_suggestions.dart';

class OrchestratorOutput {
  final String basedOnEventId;
  final List<String> goalCompletion;
  final List<OrchestratorRoleSuggestions> suggestions;
  final OrchestratorFlag? flag;

  const OrchestratorOutput({
    required this.basedOnEventId,
    required this.goalCompletion,
    required this.suggestions,
    this.flag,
  });

  static OrchestratorOutput fromJson(Map<String, dynamic> json) =>
      OrchestratorOutput(
        basedOnEventId: json["based_on_event_id"],
        goalCompletion: List<String>.from(json["goal_completion"]),
        suggestions: List.from(json["suggestions"])
            .map(
              (s) => OrchestratorRoleSuggestions.fromJson(
                Map<String, dynamic>.from(s),
              ),
            )
            .toList(),
        flag: json["flag"] != null
            ? OrchestratorFlag.fromJson(Map<String, dynamic>.from(json["flag"]))
            : null,
      );

  Map<String, dynamic> toJson() => {
    "based_on_event_id": basedOnEventId,
    "goal_completion": goalCompletion,
    "suggestions": suggestions.map((s) => s.toJson()).toList(),
    "flag": flag?.toJson(),
  };
}
