import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_settings_switch_list_tile.dart';
import 'package:fluffychat/routes/settings/settings_learning/read_aloud_voice_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// The audio section of the learning settings page: the per-surface audio
/// toggles (words, choices, on new message, on message click).
class AudioSettingsSection extends StatelessWidget {
  final LearningSettingsViewModel viewModel;

  const AudioSettingsSection({super.key, required this.viewModel});

  /// Message read-aloud only enables when the device offers a known-good voice
  /// for the selected target language; otherwise the toggle stays off and the
  /// dialog points to where a qualifying voice can be found. See
  /// message-read-aloud.instructions.md.
  Future<bool> _onEnableReadAloud(BuildContext context) async {
    final language = viewModel.selectedTargetLanguage;
    if (language == null) return false;
    if (await viewModel.refreshKnownGoodVoice()) {
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
        ...ToolSetting.audioSettings
            .where((setting) => !setting.isMessageAudioSetting)
            .map(
              (setting) => ProfileSettingsSwitchListTile.adaptive(
                defaultValue: viewModel.getToolSetting(setting),
                title: setting.toolName(context),
                subtitle: setting.toolDescription(context),
                onChange: (v) => viewModel.updateToolSetting(setting, v),
              ),
            ),
        ...ToolSetting.audioSettings
            .where((setting) => setting.isMessageAudioSetting)
            .map(
              (setting) => SwitchListTile.adaptive(
                value: viewModel.getToolSetting(setting),
                title: Text(setting.toolName(context)),
                subtitle: Text(setting.toolDescription(context)),
                activeThumbColor: AppConfig.activeToggleColor,
                onChanged: (v) async {
                  if (v) {
                    final enabled = await _onEnableReadAloud(context);
                    if (!enabled) return;
                  }
                  viewModel.updateToolSetting(setting, v);
                },
              ),
            ),
      ],
    );
  }
}
