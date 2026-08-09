import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum ToolSetting {
  interactiveTranslator,
  interactiveGrammar,
  immersionMode,
  definitions,
  autoIGC,
  audioWords,
  audioChoices,
  audioIncomingMessages,
  enableAutocorrect;

  String toolName(BuildContext context) {
    switch (this) {
      case ToolSetting.interactiveTranslator:
        return L10n.of(context).interactiveTranslatorSliderHeader;
      case ToolSetting.interactiveGrammar:
        return L10n.of(context).interactiveGrammarSliderHeader;
      case ToolSetting.immersionMode:
        return L10n.of(context).toggleImmersionMode;
      case ToolSetting.definitions:
        return L10n.of(context).definitionsToolName;
      case ToolSetting.autoIGC:
        return L10n.of(context).autoIGCToolName;
      case ToolSetting.audioWords:
        return L10n.of(context).audioWordsToolName;
      case ToolSetting.audioChoices:
        return L10n.of(context).audioChoicesToolName;
      case ToolSetting.audioIncomingMessages:
        return L10n.of(context).audioIncomingMessagesToolName;
      case ToolSetting.enableAutocorrect:
        return L10n.of(context).enableAutocorrectToolName;
    }
  }

  //use l10n to get tool name
  String toolDescription(BuildContext context) {
    switch (this) {
      case ToolSetting.interactiveTranslator:
        return L10n.of(context).itToggleDescription;
      case ToolSetting.interactiveGrammar:
        return L10n.of(context).igcToggleDescription;
      case ToolSetting.immersionMode:
        return L10n.of(context).toggleImmersionModeDesc;
      case ToolSetting.definitions:
        return L10n.of(context).definitionsToolDescription;
      case ToolSetting.autoIGC:
        return L10n.of(context).autoIGCToolDescription;
      case ToolSetting.audioWords:
        return L10n.of(context).audioWordsDescription;
      case ToolSetting.audioChoices:
        return L10n.of(context).audioChoicesDescription;
      case ToolSetting.audioIncomingMessages:
        return L10n.of(context).audioIncomingMessagesDescription;
      case ToolSetting.enableAutocorrect:
        return L10n.of(context).enableAutocorrectDescription;
    }
  }

  bool get isAvailableSetting {
    switch (this) {
      case ToolSetting.interactiveTranslator:
      case ToolSetting.interactiveGrammar:
      case ToolSetting.definitions:
      case ToolSetting.immersionMode:
      case ToolSetting.enableAutocorrect:
        return false;
      case ToolSetting.autoIGC:
      case ToolSetting.audioWords:
      case ToolSetting.audioChoices:
      case ToolSetting.audioIncomingMessages:
        return true;
    }
  }

  bool get isAudioSetting {
    switch (this) {
      case ToolSetting.audioWords:
      case ToolSetting.audioChoices:
      case ToolSetting.audioIncomingMessages:
        return true;
      default:
        return false;
    }
  }

  static List<ToolSetting> get audioSettings =>
      values.where((setting) => setting.isAudioSetting).toList();

  bool get enabled =>
      MatrixState.pangeaController.userController.isToolEnabled(this);
}
