import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

class SelectedMorphChoice {
  final MorphFeaturesEnum feature;
  final String tag;

  const SelectedMorphChoice({required this.feature, required this.tag});
}

typedef ExerciseNotifier =
    ValueNotifier<AsyncState<MultipleChoicePracticeExerciseModel>>;

/// Per-exercise interaction state (selected choices, hint visibility). Lives in
/// the session holder so it survives the practice panel closing mid-exercise.
class AnalyticsPracticeNotifier extends ChangeNotifier {
  String? _lastSelectedChoice;
  bool showHint = false;
  final Set<String> _clickedChoices = {};

  int correctAnswersSelected(MultipleChoicePracticeExerciseModel? exercise) {
    if (exercise == null) return 0;
    final allAnswers = exercise.multipleChoiceContent.answers;
    return _clickedChoices.where((c) => allAnswers.contains(c)).length;
  }

  bool enableHintPress(
    MultipleChoicePracticeExerciseModel? exercise,
    int hintsUsed,
  ) {
    if (showHint) return false;
    return switch (exercise) {
      VocabAudioPracticeExerciseModel() => true,
      _ => hintsUsed < AnalyticsPracticeConstants.maxHints,
    };
  }

  SelectedMorphChoice? selectedMorphChoice(
    MultipleChoicePracticeExerciseModel? exercise,
  ) {
    if (exercise is! MorphPracticeExerciseModel) return null;
    if (_lastSelectedChoice == null) return null;
    return SelectedMorphChoice(
      feature: exercise.morphFeature,
      tag: _lastSelectedChoice!,
    );
  }

  bool exerciseComplete(MultipleChoicePracticeExerciseModel? exercise) {
    if (exercise == null) return false;
    final allAnswers = exercise.multipleChoiceContent.answers;
    return allAnswers.every((answer) => _clickedChoices.contains(answer));
  }

  bool hasSelectedChoice(String choice) => _clickedChoices.contains(choice);

  void clearExerciseState() {
    _lastSelectedChoice = null;
    _clickedChoices.clear();
    showHint = false;
  }

  void toggleShowHint() {
    showHint = !showHint;
    notifyListeners();
  }

  void selectChoice(String choice) {
    _clickedChoices.add(choice);
    _lastSelectedChoice = choice;
    notifyListeners();
  }
}
