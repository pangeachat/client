import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';

class TutorialSequences {
  static bool hasCompletedSequence(TutorialSequence seqeunce) =>
      enabledTutorialsInSequence(seqeunce).isEmpty;

  static TutorialSequence enabledTutorialsInSequence(
    TutorialSequence sequence,
  ) => sequence.where((t) => t.globallyEnabled).toList();

  static TutorialSequence get chatTutorialSequence => [
    TutorialEnum.readingAssistance,
    TutorialEnum.selectModeButtons,
    TutorialEnum.writingAssistance,
  ];
}
