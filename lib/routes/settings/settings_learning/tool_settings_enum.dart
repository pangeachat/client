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
  listenFirst,
  audioOnNewMessage,
  audioOnMessageClick,
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
      case ToolSetting.listenFirst:
        return L10n.of(context).listenFirst;
      case ToolSetting.audioOnNewMessage:
        return L10n.of(context).audioOnNewMessageToolName;
      case ToolSetting.audioOnMessageClick:
        return L10n.of(context).audioOnMessageClickToolName;
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
      case ToolSetting.listenFirst:
        return L10n.of(context).listenFirstDescription;
      case ToolSetting.audioOnNewMessage:
        return L10n.of(context).audioOnNewMessageDescription;
      case ToolSetting.audioOnMessageClick:
        return L10n.of(context).audioOnMessageClickDescription;
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
      case ToolSetting.listenFirst:
      case ToolSetting.audioOnNewMessage:
      case ToolSetting.audioOnMessageClick:
        return true;
    }
  }

  bool get isAudioSetting {
    switch (this) {
      case ToolSetting.audioWords:
      case ToolSetting.audioChoices:
      case ToolSetting.listenFirst:
      case ToolSetting.audioOnNewMessage:
      case ToolSetting.audioOnMessageClick:
        return true;
      default:
        return false;
    }
  }

  /// Listen First only reorders what a tap on a choice does with the audio
  /// [ToolSetting.audioChoices] permits — with that gate shut it is a mode
  /// that plays nothing, so it is offered as unavailable rather than as a
  /// toggle that silently does nothing.
  bool get requiresChoiceAudio => this == ToolSetting.listenFirst;

  /// The message read-aloud toggles, which enable through the known-good-voice
  /// gate rather than directly. See message-read-aloud.instructions.md.
  bool get isMessageAudioSetting =>
      this == ToolSetting.audioOnNewMessage ||
      this == ToolSetting.audioOnMessageClick;

  static List<ToolSetting> get audioSettings =>
      values.where((setting) => setting.isAudioSetting).toList();

  bool get enabled =>
      MatrixState.pangeaController.userController.isToolEnabled(this);
}
