import 'package:fluffychat/pangea/instructions/instructions_enum.dart';

enum TutorialEnum {
  readingAssistance(stepCount: 1),
  writingAssistance(stepCount: 2),
  selectModeButtons(stepCount: 3);

  const TutorialEnum({required this.stepCount});
  final int stepCount;
}

extension TutorialEnumExtension on TutorialEnum {
  InstructionsEnum get _instructionsEnum => switch (this) {
    TutorialEnum.readingAssistance =>
      InstructionsEnum.readingAssistanceTutorial,
    TutorialEnum.writingAssistance =>
      InstructionsEnum.writingAssistanceTutorial,
    TutorialEnum.selectModeButtons =>
      InstructionsEnum.selectModeButtonsTutorial,
  };

  bool get hasBeenSeen => _instructionsEnum.isToggledOff;

  void markSeen() => _instructionsEnum.setToggledOff(true);
}
