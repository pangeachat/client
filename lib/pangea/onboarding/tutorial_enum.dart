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

    return subscribed && !_hasBeenSeen;
  }

  bool locallyEnabled(String? currentRoute) {
    if (!globallyEnabled) return false;
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

  void markSeen() => _instructionsEnum.setToggledOff(true);
}
