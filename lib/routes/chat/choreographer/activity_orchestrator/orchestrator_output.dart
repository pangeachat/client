import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_flag.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_goal_completion.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';

class OrchestratorOutput {
  final String basedOnEventId;
  final List<OrchestratorRoleGoalCompletion> goalCompletion;
  final List<OrchestratorRoleSuggestions> suggestions;
  final OrchestratorFlag? flag;

  const OrchestratorOutput({
    required this.basedOnEventId,
    required this.goalCompletion,
    required this.suggestions,
    this.flag,
  });

  List<OrchestratorRoleSuggestions> suggestionsByRoleId(String roleId) =>
      suggestions.where((s) => s.roleId == roleId).toList();

  static OrchestratorOutput fromJson(
    Map<String, dynamic> json,
  ) => OrchestratorOutput(
    basedOnEventId: json["based_on_event_id"],
    // An old bot may still broadcast flat string ids; those cannot
    // be attributed to a role and are ignored rather than thrown on.
    goalCompletion: List.from(json["goal_completion"] ?? [])
        .whereType<Map>()
        .map(
          (b) => OrchestratorRoleGoalCompletion.fromJson(
            Map<String, dynamic>.from(b),
          ),
        )
        .toList(),
    // v2 (choreo#2761): Reaction buckets and turn-0 null buckets arrive from
    // the bot's adapter as empty options lists — they are emitted for
    // uniformity and deliberately never rendered, so drop them here along
    // with malformed buckets. Valid sibling buckets are kept.
    suggestions: List.from(json["suggestions"] ?? [])
        .whereType<Map>()
        .where((s) => s["role_id"] is String)
        .map(
          (s) => OrchestratorRoleSuggestions.fromJson(
            Map<String, dynamic>.from(s),
          ),
        )
        .where((s) => s.suggestions.isNotEmpty)
        .toList(),
    flag: json["flag"] != null
        ? OrchestratorFlag.fromJson(Map<String, dynamic>.from(json["flag"]))
        : null,
  );

  Map<String, dynamic> toJson() => {
    "based_on_event_id": basedOnEventId,
    "goal_completion": goalCompletion.map((b) => b.toJson()).toList(),
    "suggestions": suggestions.map((s) => s.toJson()).toList(),
    "flag": flag?.toJson(),
  };
}
