import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/practice_activity_model.dart';
import 'package:flutter/material.dart';

class MultipleChoice {
  final String question;
  final List<String> choices;
  final String answer;
  final RelevantSpanDisplayDetails? spanDisplayDetails;

  MultipleChoice({
    required this.question,
    required this.choices,
    required this.answer,
    required this.spanDisplayDetails,
  });

  bool isCorrect(int index) => index == correctAnswerIndex;

  bool get isValidQuestion => choices.contains(answer);

  int get correctAnswerIndex => choices.indexOf(answer);

  int choiceIndex(String choice) => choices.indexOf(choice);

  Color choiceColor(int index) =>
      index == correctAnswerIndex ? AppConfig.success : AppConfig.warning;

  factory MultipleChoice.fromJson(Map<String, dynamic> json) {
    final spanDisplay = json['span_display_details'] != null &&
            json['span_display_details'] is Map
        ? RelevantSpanDisplayDetails.fromJson(json['span_display_details'])
        : null;
    return MultipleChoice(
      question: json['question'] as String,
      choices: (json['choices'] as List).map((e) => e as String).toList(),
      answer: json['answer'] ?? json['correct_answer'] as String,
      spanDisplayDetails: spanDisplay,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      'choices': choices,
      'answer': answer,
      'span_display_details': spanDisplayDetails?.toJson(),
    };
  }
}
