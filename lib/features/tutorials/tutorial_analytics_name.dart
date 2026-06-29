import 'package:fluffychat/features/tutorials/tutorial_enum.dart';

enum TutorialAnalyticsName {
  onboarding,
  readingAssistance,
  writingAssistance,
  selectModeButtons,
}

extension TutorialEnumAnalyticsName on TutorialEnum {
  TutorialAnalyticsName get analyticsName => switch (this) {
    TutorialEnum.readingAssistance => TutorialAnalyticsName.readingAssistance,
    TutorialEnum.writingAssistance => TutorialAnalyticsName.writingAssistance,
    TutorialEnum.selectModeButtons => TutorialAnalyticsName.selectModeButtons,
  };
}
