/// Cumulative completed goal ids for one role from an orchestrator output.
///
/// Goals are fulfilled and awarded per role; a goal shared across roles
/// completes independently for each role.
class OrchestratorRoleGoalCompletion {
  final String roleId;
  final List<String> goalIds;

  const OrchestratorRoleGoalCompletion({
    required this.roleId,
    required this.goalIds,
  });

  static OrchestratorRoleGoalCompletion fromJson(Map<String, dynamic> json) =>
      OrchestratorRoleGoalCompletion(
        roleId: json["role_id"],
        goalIds: List<String>.from(json["goal_ids"] ?? []),
      );

  Map<String, dynamic> toJson() => {"role_id": roleId, "goal_ids": goalIds};
}
