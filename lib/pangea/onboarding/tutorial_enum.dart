enum TutorialEnum {
  readingAssistance(stepCount: 1),
  writingAssistance(stepCount: 2),
  selectModeButtons(stepCount: 3);

  const TutorialEnum({required this.stepCount});
  final int stepCount;
}
