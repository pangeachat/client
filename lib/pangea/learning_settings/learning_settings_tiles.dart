import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/language_level_dropdown.dart';
import 'package:fluffychat/pangea/instructions/reset_instructions_list_tile.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/country_picker_tile.dart';
import 'package:fluffychat/pangea/learning_settings/enable_autocorrect_dialog.dart';
import 'package:fluffychat/pangea/learning_settings/gender_dropdown.dart';
import 'package:fluffychat/pangea/learning_settings/learning_settings_view_model.dart';
import 'package:fluffychat/pangea/learning_settings/p_language_dropdown.dart';
import 'package:fluffychat/pangea/learning_settings/p_settings_switch_list_tile.dart';
import 'package:fluffychat/pangea/learning_settings/tool_settings_enum.dart';
import 'package:fluffychat/pangea/learning_settings/voice_dropdown.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LearningSettingsTiles extends StatelessWidget {
  final LearningSettingsViewModel viewModel;
  final ValueNotifier<String?> languageErrorNotifier;
  final TextEditingController aboutTextController;

  const LearningSettingsTiles({
    super.key,
    required this.viewModel,
    required this.languageErrorNotifier,
    required this.aboutTextController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTileTheme(
      iconColor: theme.colorScheme.onSurface,
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => Column(
          children: [
            ValueListenableBuilder(
              valueListenable: languageErrorNotifier,
              builder: (context, error, _) => _LanguageSettingsExpansionTile(
                viewModel: viewModel,
                error: error,
              ),
            ),
            _UserProfileExpansionTile(
              viewModel: viewModel,
              aboutTextController: aboutTextController,
            ),
            _LearningSettingsExpansionTile(
              viewModel: viewModel,
              onEnableAutocorrect: () => showDialog(
                context: context,
                builder: (context) => EnableAutocorrectDialog(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSettingsExpansionTile extends StatelessWidget {
  final LearningSettingsViewModel viewModel;
  final String? error;

  const _LanguageSettingsExpansionTile({required this.viewModel, this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      initiallyExpanded: true,
      shape: Border(top: BorderSide(width: 1, color: Colors.transparent)),
      collapsedShape: Border(
        top: BorderSide(width: 1, color: Colors.transparent),
      ),
      title: Text(
        L10n.of(context).languages,
        style: TextStyle(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      ),
      children: [
        SizedBox(height: 8.0),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: PLanguageDropdown(
            onChange: (lang) =>
                viewModel.setSelectedLanguage(sourceLanguage: lang),
            initialLanguage:
                viewModel.selectedSourceLanguage ?? LanguageModel.unknown,
            languages: MatrixState.pangeaController.pLanguageStore.baseOptions,
            isL2List: false,
            decorationText: L10n.of(context).myBaseLanguage,
            hasError: error != null,
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: PLanguageDropdown(
            onChange: (lang) =>
                viewModel.setSelectedLanguage(targetLanguage: lang),
            initialLanguage: viewModel.selectedTargetLanguage,
            languages:
                MatrixState.pangeaController.pLanguageStore.targetOptions,
            isL2List: true,
            decorationText: L10n.of(context).iWantToLearn,
            error: error,
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
          ),
        ),
        SizedBox(height: 8.0),
      ],
    );
  }
}

class _UserProfileExpansionTile extends StatelessWidget {
  final LearningSettingsViewModel viewModel;
  final TextEditingController aboutTextController;
  const _UserProfileExpansionTile({
    required this.viewModel,
    required this.aboutTextController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      shape: Border(top: BorderSide(width: 1, color: theme.dividerColor)),
      collapsedShape: Border(
        top: BorderSide(width: 1, color: theme.dividerColor),
      ),
      title: Text(
        L10n.of(context).profile,
        style: TextStyle(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      ),
      children: [
        SizedBox(height: 8.0),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: LanguageLevelDropdown(
            initialLevel: viewModel.cefrLevel,
            onChanged: viewModel.setCefrLevel,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: CountryPickerDropdown(viewModel.country, viewModel.setCountry),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: GenderDropdown(
            initialGender: viewModel.gender,
            onChanged: viewModel.setGender,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: TextField(
            controller: aboutTextController,
            decoration: InputDecoration(
              hintText: L10n.of(context).aboutMeHint,
              labelText: L10n.of(context).aboutMeHint,
            ),
            onChanged: (val) => viewModel.setAbout(val),
            minLines: 1,
            maxLines: 3,
            maxLength: 100,
          ),
        ),
        SwitchListTile.adaptive(
          value: viewModel.publicProfile,
          onChanged: viewModel.setPublicProfile,
          title: Text(L10n.of(context).publicProfileTitle),
          subtitle: Text(L10n.of(context).publicProfileDesc),
          activeThumbColor: AppConfig.activeToggleColor,
        ),
        SizedBox(height: 8.0),
      ],
    );
  }
}

class _LearningSettingsExpansionTile extends StatelessWidget {
  final LearningSettingsViewModel viewModel;
  final VoidCallback onEnableAutocorrect;
  const _LearningSettingsExpansionTile({
    required this.viewModel,
    required this.onEnableAutocorrect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      shape: Border(top: BorderSide(width: 1, color: theme.dividerColor)),
      collapsedShape: Border(
        top: BorderSide(width: 1, color: theme.dividerColor),
      ),
      title: Text(
        L10n.of(context).learningSettings,
        style: TextStyle(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      ),
      children: [
        SizedBox(height: 8.0),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
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
                onChange: (v) {
                  viewModel.updateToolSetting(setting, v);
                  if (v && setting == ToolSetting.enableAutocorrect) {
                    onEnableAutocorrect();
                  }
                },
              ),
            ),
        ResetInstructionsListTile(viewModel.resetInstructionTooltips),
        SizedBox(height: 8.0),
      ],
    );
  }
}
