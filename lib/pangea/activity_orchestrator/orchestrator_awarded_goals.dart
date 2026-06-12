/// Per-role cumulative goal awards from orchestrator outputs.
///
/// Goals are fulfilled and awarded per role; a goal shared across roles
/// completes independently for each role. `awards` maps role id to that
/// role's awarded goal ids.
///
/// Reads both state shapes: the current per-role
/// `{"awards": {role_id: [goal_ids]}}` and the pre-per-role flat
/// `{"goal_ids": [...]}`. A flat id counts as completed for any role that
/// declares the goal (callers only ask about ids from a role's own goals
/// list), matching the bot's expansion semantics.
class OrchestratorAwardedGoals {
  final Map<String, List<String>> awards;
  final List<String> legacyFlatGoalIds;

  const OrchestratorAwardedGoals({
    this.awards = const {},
    this.legacyFlatGoalIds = const [],
  });

  bool isGoalCompletedForRole(String roleId, String goalId) =>
      (awards[roleId]?.contains(goalId) ?? false) ||
      legacyFlatGoalIds.contains(goalId);

  static OrchestratorAwardedGoals fromJson(Map<String, dynamic> json) {
    if (json["awards"] == null && json["goal_ids"] != null) {
      return OrchestratorAwardedGoals(
        legacyFlatGoalIds: List<String>.from(json["goal_ids"]),
      );
    }
    return OrchestratorAwardedGoals(
      awards: Map<String, dynamic>.from(json["awards"] ?? {}).map(
        (roleId, goalIds) => MapEntry(roleId, List<String>.from(goalIds)),
      ),
      legacyFlatGoalIds: List<String>.from(json["legacy_flat_goal_ids"] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    "awards": awards,
    "legacy_flat_goal_ids": legacyFlatGoalIds,
  };
}
