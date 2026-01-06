import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';

class MultipleChoiceActivity {
  /// choices, including the correct answer
  final Set<String> choices;
  final Set<String> answers;

  MultipleChoiceActivity({
    required this.choices,
    required this.answers,
  });

  Color choiceColor(String value) =>
      answers.contains(value) ? AppConfig.success : AppConfig.warning;

  bool isCorrect(String value) => answers.contains(value);

  factory MultipleChoiceActivity.fromJson(Map<String, dynamic> json) {
    final answerEntry = json['answer'] ?? json['correct_answer'] ?? "";
    List<String> answers = [];
    if (answerEntry is String) {
      answers = [answerEntry];
    } else if (answerEntry is List) {
      answers = answerEntry.map((e) => e as String).toList();
    }

    return MultipleChoiceActivity(
      choices: (json['choices'] as List).map((e) => e as String).toSet(),
      answers: answers.toSet(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'choices': List.from(choices),
      'answer': List.from(answers),
    };
  }

  // ovveride operator == and hashCode
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MultipleChoiceActivity &&
        other.choices == choices &&
        const ListEquality().equals(other.answers.sorted(), answers.sorted());
  }

  @override
  int get hashCode {
    return choices.hashCode ^ Object.hashAll(answers);
  }
}
