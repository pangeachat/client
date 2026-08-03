import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/language_level_dropdown.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/enable_autocorrect_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_language_dropdown.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_settings_switch_list_tile.dart';
import 'package:fluffychat/routes/settings/settings_learning/read_aloud_voice_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/voice_dropdown.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LearningSettingsTiles extends StatelessWidget {
  final LearningSettingsViewModel viewModel;
  final ValueNotifier<String?> languageErrorNotifier;

  const LearningSettingsTiles({
    super.key,
    required this.viewModel,
    required this.languageErrorNotifier,
  });

  Future<bool> onEnableAutocorrect(BuildContext context) async {
    final resp = await showDialog(
      context: context,
      builder: (context) => EnableAutocorrectDialog(),
    );
    return resp == false ? false : true;
  }

  /// Auto-read-aloud only enables when the device offers a known-good voice
  /// for the selected target language; otherwise the toggle stays off and the
  /// dialog points to where a qualifying voice can be found. See
  /// message-read-aloud.instructions.md.
  Future<bool> onEnableReadAloud(BuildContext context) async {
    final language = viewModel.selectedTargetLanguage;
    if (language == null) return false;
    if (await TtsController.hasKnownGoodVoiceFor(language.langCode)) {
      return true;
    }
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (context) =>
            ReadAloudVoiceDialog(language: language.displayName),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTileTheme(
      iconColor: theme.colorScheme.onSurface,
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => Column(
          spacing: 16.0,
          children: [
            Column(
              children: [
                ValueListenableBuilder(
                  valueListenable: languageErrorNotifier,
                  builder: (context, error, _) => Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 16.0,
                        ),
                        child: PLanguageDropdown(
                          onChange: (lang) => viewModel.setSelectedLanguage(
                            sourceLanguage: lang,
                          ),
                          initialLanguage:
                              viewModel.selectedSourceLanguage ??
                              LanguageModel.unknown,
                          languages: MatrixState
                              .pangeaController
                              .pLanguageStore
                              .baseOptions,
                          isL2List: false,
                          decorationText: L10n.of(context).myBaseLanguage,
                          hasError: error != null,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHigh,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 16.0,
                        ),
                        child: PLanguageDropdown(
                          onChange: (lang) => viewModel.setSelectedLanguage(
                            targetLanguage: lang,
                          ),
                          initialLanguage: viewModel.selectedTargetLanguage,
                          languages: MatrixState
                              .pangeaController
                              .pLanguageStore
                              .targetOptions,
                          isL2List: true,
                          decorationText: L10n.of(context).iWantToLearn,
                          error: error,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 16.0,
                  ),
                  child: LanguageLevelDropdown(
                    initialLevel: viewModel.cefrLevel,
                    onChanged: viewModel.setCefrLevel,
                  ),
                ),
              ],
            ),
            Divider(height: 1),
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 16.0,
                  ),
                  child: VoiceDropdown(
                    value: viewModel.selectedVoice,
                    language: viewModel.selectedTargetLanguage,
                    onChanged: viewModel.setVoice,
                  ),
                ),
                ...ToolSetting.values
                    .where((tool) => tool.isAvailableSetting)
                    .map(
                      (setting) => ProfileSettingsSwitchListTile.adaptive(
                        defaultValue: viewModel.getToolSetting(setting),
                        title: setting.toolName(context),
                        subtitle: setting.toolDescription(context),
                        onChange: (v) =>
                            viewModel.updateToolSetting(setting, v),
                      ),
                    ),
                SwitchListTile.adaptive(
                  value: viewModel.getToolSetting(
                    ToolSetting.autoReadAloudMessages,
                  ),
                  title: Text(
                    ToolSetting.autoReadAloudMessages.toolName(context),
                  ),
                  subtitle: Text(
                    ToolSetting.autoReadAloudMessages.toolDescription(context),
                  ),
                  activeThumbColor: AppConfig.activeToggleColor,
                  onChanged: (v) async {
                    if (v) {
                      final enabled = await onEnableReadAloud(context);
                      if (!enabled) return;
                    }
                    viewModel.updateToolSetting(
                      ToolSetting.autoReadAloudMessages,
                      v,
                    );
                  },
                ),
                SwitchListTile.adaptive(
                  value: viewModel.getToolSetting(
                    ToolSetting.enableAutocorrect,
                  ),
                  title: Text(ToolSetting.enableAutocorrect.toolName(context)),
                  subtitle: Text(
                    ToolSetting.enableAutocorrect.toolDescription(context),
                  ),
                  activeThumbColor: AppConfig.activeToggleColor,
                  onChanged: (v) async {
                    if (v) {
                      final enabled = await onEnableAutocorrect(context);
                      if (!enabled) return;
                    }
                    viewModel.updateToolSetting(
                      ToolSetting.enableAutocorrect,
                      v,
                    );
                  },
                ),
                SwitchListTile.adaptive(
                  value: viewModel.appLanguageIsTarget,
                  title: Text(L10n.of(context).appInTargetLanguageTitle),
                  subtitle: Text(L10n.of(context).appInTargetLanguageDesc),
                  activeThumbColor: AppConfig.activeToggleColor,
                  onChanged: viewModel.setAppLanguageIsTarget,
                ),
                ListTile(
                  leading: const Icon(Icons.lightbulb),
                  title: Text(L10n.of(context).resetInstructionTooltipsTitle),
                  subtitle: Text(L10n.of(context).resetInstructionTooltipsDesc),
                  selected: viewModel.hasResetTooltips,
                  onTap: viewModel.hasResetTooltips
                      ? null
                      : viewModel.resetInstructionTooltips,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
