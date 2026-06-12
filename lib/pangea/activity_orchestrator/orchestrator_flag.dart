class OrchestratorFlag {
  final String reason;
  final String evidence;

  const OrchestratorFlag({required this.reason, required this.evidence});

  static OrchestratorFlag fromJson(Map<String, dynamic> json) =>
      OrchestratorFlag(reason: json["reason"], evidence: json["evidence"]);

  Map<String, dynamic> toJson() => {"reason": reason, "evidence": evidence};
}
