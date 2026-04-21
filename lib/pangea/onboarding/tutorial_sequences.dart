import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';

class TutorialSequences {
  static TutorialSequence get chatTutorialSequence => [
    TutorialEnum.readingAssistance,
    TutorialEnum.selectModeButtons,
    TutorialEnum.writingAssistance,
  ];
}
