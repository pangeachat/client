import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum TutorialEnum {
  readingAssistance(
    stepCount: 1,
    showNavigationButtons: false,
    route: ':roomid',
  ),
  writingAssistance(
    stepCount: 1,
    showNavigationButtons: false,
    route: ':roomid',
  ),
  selectModeButtons(
    stepCount: 3,
    showNavigationButtons: false,
    route: ':roomid',
  );

  final int stepCount;
  final String route;
  final bool showNavigationButtons;

  const TutorialEnum({
    required this.stepCount,
    required this.route,
    this.showNavigationButtons = true,
  });

  bool get globallyEnabled {
    final subscribed =
        MatrixState.pangeaController.subscriptionController.isSubscribed !=
        false;

    return subscribed && !_hasBeenSeen && stepProgress < stepCount;
  }

  bool locallyEnabled(String? currentRoute) {
    return currentRoute == route;
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
