import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum TutorialEnum {
  readingAssistance(stepCount: 1, showNavigationButtons: false),
  writingAssistance(stepCount: 1, showNavigationButtons: false),
  selectModeButtons(stepCount: 3, showNavigationButtons: false);

  final int stepCount;
  final bool showNavigationButtons;

  const TutorialEnum({
    required this.stepCount,
    this.showNavigationButtons = true,
  });

  bool get enabled {
    final subscribed =
        MatrixState.pangeaController.subscriptionController.isSubscribed !=
        false;
    return subscribed && !_hasBeenSeen;
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

  void markSeen() => _instructionsEnum.setToggledOff(true);
}
