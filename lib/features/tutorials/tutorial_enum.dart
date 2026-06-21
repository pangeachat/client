import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum TutorialEnum {
  readingAssistance(stepCount: 1, showNavigationButtons: false),
  writingAssistance(stepCount: 1, showNavigationButtons: false),
  selectModeButtons(stepCount: 4, showNavigationButtons: false);

  final int stepCount;
  final bool showNavigationButtons;

  const TutorialEnum({
    required this.stepCount,
    this.showNavigationButtons = true,
  });

  bool get globallyEnabled {
    if (!MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent) {
      return false;
    }

    return !_hasBeenSeen && stepProgress < stepCount;
  }

  /// Whether this tutorial may run on the current surface. Every tutorial is
  /// chat-scoped, so the gate is simply whether the chat panel is focused.
  bool locallyEnabled(bool isFocused) {
    return isFocused;
  }

  InstructionsEnum get _instructionsEnum => switch (this) {
    TutorialEnum.readingAssistance =>
      InstructionsEnum.readingAssistanceTutorial,
    TutorialEnum.writingAssistance =>
      InstructionsEnum.writingAssistanceTutorial,
    TutorialEnum.selectModeButtons =>
      InstructionsEnum.selectModeButtonsTutorial,
  };

  bool get _hasBeenSeen => _instructionsEnum.isToggledOff;

  void _markSeen() {
    _instructionsEnum.setToggledOff(true);
    _instructionsEnum.clearStepProgress();
  }

  /// The step index to resume from on the next launch of this tutorial.
  /// Returns 0 if no progress has been saved yet.
  int get stepProgress => _instructionsEnum.stepProgress;

  /// Persists [stepIndex] so the user can resume mid-tutorial on the next
  /// launch. Called after each successful step advance in the overlay widget.
  void saveProgress(int stepIndex) {
    if (stepIndex >= stepCount) {
      _markSeen();
      return;
    }
    _instructionsEnum.setStepProgress(stepIndex);
  }
}
