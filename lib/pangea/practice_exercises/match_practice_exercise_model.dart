import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_choice.dart';

class MatchPracticeExercise {
  /// The constructIdenfifiers involved in the exercise
  /// and the forms that are acceptable answers
  final Map<ConstructForm, List<String>> matchInfo;

  List<PracticeExerciseChoice> choices = List.empty(growable: true);

  MatchPracticeExercise({required this.matchInfo}) {
    for (final ith in matchInfo.entries) {
      debugPrint('Construct: ${ith.key.form}, Forms: ${ith.value}');
    }

    final List<String> usedForms = [];
    for (final matchEntry in matchInfo.entries) {
      if (matchEntry.value.isEmpty) {
        throw Exception("No forms available for construct ${matchEntry.key}");
      }

      final String choiceContent = matchEntry.value.firstWhere(
        (element) => !usedForms.contains(element),
        orElse: () => throw Exception(
          "No unique form available for construct ${matchEntry.key.form}",
        ),
      );

      choices.add(
        PracticeExerciseChoice(
          choiceContent: choiceContent,
          form: matchEntry.key,
        ),
      );

      usedForms.add(choiceContent);
      debugPrint(
        'Added PracticeChoice Construct: ${matchEntry.key}, Forms: ${matchEntry.value}',
      );
    }

    choices.sort(
      (a, b) => a.choiceContent.length.compareTo(b.choiceContent.length),
    );
  }

  factory MatchPracticeExercise.fromJson(Map<String, dynamic> json) {
    final Map<ConstructForm, List<String>> matchInfo = {};
    for (final constructJson in json['match_info']) {
      final ConstructForm cId = ConstructForm.fromJson(constructJson['cId']);
      final List<String> surfaceForms = List<String>.from(
        constructJson['forms'],
      );
      matchInfo[cId] = surfaceForms;
    }

    return MatchPracticeExercise(matchInfo: matchInfo);
  }

  Map<String, dynamic> toJson() {
    final List<Map<String, dynamic>> matchInfo = [];
    for (final cId in this.matchInfo.keys) {
      matchInfo.add({'cId': cId.toJson(), 'forms': this.matchInfo[cId]});
    }

    return {'match_info': matchInfo};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MatchPracticeExercise &&
        const MapEquality().equals(other.matchInfo, matchInfo);
  }

  @override
  int get hashCode => const MapEquality().hash(matchInfo);
}
