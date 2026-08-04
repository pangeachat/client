import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_settings_switch_list_tile.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/voice_dropdown.dart';

/// The audio section of the learning settings page: the bot voice dropdown
/// plus the per-surface audio toggles (words, choices, incoming messages).
class AudioSettingsSection extends StatelessWidget {
  final LearningSettingsViewModel viewModel;

  const AudioSettingsSection({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ListTile(
          title: Text(
            L10n.of(context).audioSectionTitle,
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: VoiceDropdown(
            value: viewModel.selectedVoice,
            language: viewModel.selectedTargetLanguage,
            onChanged: viewModel.setVoice,
          ),
        ),
        ...ToolSetting.audioSettings.map(
          (setting) => ProfileSettingsSwitchListTile.adaptive(
            defaultValue: viewModel.getToolSetting(setting),
            title: setting.toolName(context),
            subtitle: setting.toolDescription(context),
            onChange: (v) => viewModel.updateToolSetting(setting, v),
          ),
        ),
      ],
    );
  }
}
