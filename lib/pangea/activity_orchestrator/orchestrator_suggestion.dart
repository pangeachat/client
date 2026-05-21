import 'package:flutter/material.dart';

enum OrchestratorSuggestionType {
  best,
  distractor;

  bool get isSuggestion => this == OrchestratorSuggestionType.best;

  Color get color {
    switch (this) {
      case OrchestratorSuggestionType.best:
        return Colors.green;
      case OrchestratorSuggestionType.distractor:
        return Colors.red;
    }
  }
}

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
