enum OrchestratorSuggestionType { best, distractor }

class OrchestratorSuggestion {
  final String text;
  final OrchestratorSuggestionType type;

  const OrchestratorSuggestion({required this.text, required this.type});

  static OrchestratorSuggestion fromJson(Map<String, dynamic> json) =>
      OrchestratorSuggestion(
        text: json["text"],
        type: OrchestratorSuggestionType.values.firstWhere(
          (v) => v.name == json["type"],
        ),
      );

  Map<String, dynamic> toJson() => {"text": text, "type": type};
}
