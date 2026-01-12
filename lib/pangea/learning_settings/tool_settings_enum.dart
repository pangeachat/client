import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum ToolSetting {
  interactiveTranslator,
  interactiveGrammar,
  immersionMode,
  definitions,
  autoIGC,
  enableTTS,
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
      case ToolSetting.enableTTS:
        return L10n.of(context).enableTTSToolName;
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
      case ToolSetting.enableTTS:
        return L10n.of(context).enableTTSToolDescription;
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
        return false;
      case ToolSetting.autoIGC:
      case ToolSetting.enableTTS:
      case ToolSetting.enableAutocorrect:
        return true;
    }
  }

  bool get enabled =>
      MatrixState.pangeaController.userController.isToolEnabled(this);
}
