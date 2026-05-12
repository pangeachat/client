class OrchestratorAwardedGoals {
  final List<String> goalIds;
  const OrchestratorAwardedGoals({required this.goalIds});

  static OrchestratorAwardedGoals fromJson(Map<String, dynamic> json) =>
      OrchestratorAwardedGoals(goalIds: List<String>.from(json["goal_ids"]));

  Map<String, dynamic> toJson() => {"goal_ids": goalIds};
}
