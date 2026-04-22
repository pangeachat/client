import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum InstructionsEnum {
  clickMessage,
  chooseLemmaMeaning,
  ttsDisabled,
  chooseEmoji,
  chooseWordAudio,
  chooseMorphs,
  analyticsVocabList,
  morphAnalyticsList,
  activityAnalyticsList,
  levelAnalytics,
  emptyChatWarning,
  activityStatsMenu,
  chatParticipantTooltip,
  courseParticipantTooltip,
  noSavedActivitiesYet,
  setLemmaEmoji,
  disableLanguageTools,
  selectMeaning,
  dismissSupportChat,
  shimmerNewToken,
  shimmerTranslation,
  showedActivityMenu,
  courseDescription,
  readingAssistanceTutorial,
  writingAssistanceTutorial,
  selectModeButtonsTutorial,
}

extension InstructionsEnumExtension on InstructionsEnum {
  String title(L10n l10n) {
    switch (this) {
      case InstructionsEnum.clickMessage:
        return l10n.clickMessageTitle;
      case InstructionsEnum.ttsDisabled:
        return l10n.ttsDisbledTitle;
      case InstructionsEnum.chooseWordAudio:
      case InstructionsEnum.selectMeaning:
      case InstructionsEnum.chooseEmoji:
      case InstructionsEnum.chooseLemmaMeaning:
      case InstructionsEnum.chooseMorphs:
      case InstructionsEnum.analyticsVocabList:
      case InstructionsEnum.morphAnalyticsList:
      case InstructionsEnum.activityStatsMenu:
      case InstructionsEnum.chatParticipantTooltip:
      case InstructionsEnum.courseParticipantTooltip:
      case InstructionsEnum.activityAnalyticsList:
      case InstructionsEnum.levelAnalytics:
      case InstructionsEnum.noSavedActivitiesYet:
      case InstructionsEnum.setLemmaEmoji:
      case InstructionsEnum.disableLanguageTools:
      case InstructionsEnum.dismissSupportChat:
      case InstructionsEnum.shimmerNewToken:
      case InstructionsEnum.shimmerTranslation:
      case InstructionsEnum.showedActivityMenu:
      case InstructionsEnum.courseDescription:
      case InstructionsEnum.readingAssistanceTutorial:
      case InstructionsEnum.writingAssistanceTutorial:
      case InstructionsEnum.selectModeButtonsTutorial:
        ErrorHandler.logError(
          e: Exception("No title for this instruction"),
          m: 'InstructionsEnumExtension.title',
          data: {'this': this},
        );
        debugger(when: kDebugMode);
        return "";
      case InstructionsEnum.emptyChatWarning:
        return l10n.emptyChatWarningTitle;
    }
  }

  String body(L10n l10n) {
    switch (this) {
      case InstructionsEnum.clickMessage:
        return l10n.clickMessageBody;
      case InstructionsEnum.chooseLemmaMeaning:
        return l10n.chooseLemmaMeaningInstructionsBody;
      case InstructionsEnum.chooseEmoji:
        return l10n.chooseEmojiInstructionsBody;
      case InstructionsEnum.ttsDisabled:
        return l10n.ttsDisabledBody;
      case InstructionsEnum.chooseWordAudio:
        return l10n.chooseWordAudioInstructionsBody;
      case InstructionsEnum.chooseMorphs:
        return l10n.chooseMorphsInstructionsBody;
      case InstructionsEnum.analyticsVocabList:
        return l10n.analyticsVocabListBody;
      case InstructionsEnum.morphAnalyticsList:
        return l10n.morphAnalyticsListBody;
      case InstructionsEnum.activityAnalyticsList:
        return l10n.activityAnalyticsTooltipBody;
      case InstructionsEnum.emptyChatWarning:
        return l10n.emptyChatWarningDesc;
      case InstructionsEnum.activityStatsMenu:
        return l10n.activityStatsButtonInstruction;
      case InstructionsEnum.chatParticipantTooltip:
        return l10n.chatParticipantTooltip;
      case InstructionsEnum.courseParticipantTooltip:
        return l10n.courseParticipantTooltip;
      case InstructionsEnum.levelAnalytics:
        return l10n.levelInfoTooltip;
      case InstructionsEnum.noSavedActivitiesYet:
        return l10n.noSavedActivitiesYet;
      case InstructionsEnum.setLemmaEmoji:
      case InstructionsEnum.dismissSupportChat:
      case InstructionsEnum.shimmerNewToken:
      case InstructionsEnum.shimmerTranslation:
      case InstructionsEnum.showedActivityMenu:
      case InstructionsEnum.readingAssistanceTutorial:
      case InstructionsEnum.writingAssistanceTutorial:
      case InstructionsEnum.selectModeButtonsTutorial:
        return "";
      case InstructionsEnum.disableLanguageTools:
        return l10n.disableLanguageToolsDesc;
      case InstructionsEnum.selectMeaning:
        return l10n.selectMeaning;
      case InstructionsEnum.courseDescription:
        return l10n.courseDescription;
    }
  }

  bool get isToggledOff {
    final user = MatrixState.pangeaController.userController;
    // default to having shown the instruction to avoid showing it again
    if (!user.initCompleter.isCompleted) return true;
    return user.profile.instructionSettings.getStatus(this);
  }

  void setToggledOff(bool value) {
    if (isToggledOff == value) return;
    MatrixState.pangeaController.userController.updateProfile((profile) {
      profile.instructionSettings.setStatus(this, value);
      return profile;
    });
  }

  /// The last step index the user reached in this tutorial, or 0 if no
  /// progress has been saved.
  int get stepProgress {
    final user = MatrixState.pangeaController.userController;
    if (!user.initCompleter.isCompleted) return 0;
    return user.profile.instructionSettings.getStepProgress(this);
  }

  void setStepProgress(int step) {
    MatrixState.pangeaController.userController.updateProfile((profile) {
      profile.instructionSettings.setStepProgress(this, step);
      return profile;
    });
  }

  void clearStepProgress() {
    MatrixState.pangeaController.userController.updateProfile((profile) {
      profile.instructionSettings.clearStepProgress(this);
      return profile;
    });
  }
}
