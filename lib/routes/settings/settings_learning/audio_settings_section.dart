import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_settings_switch_list_tile.dart';
import 'package:fluffychat/routes/settings/settings_learning/read_aloud_voice_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/voice_dropdown.dart';

/// The audio section of the learning settings page: the bot voice dropdown
/// plus the per-surface audio toggles (words, choices, incoming messages).
class AudioSettingsSection extends StatelessWidget {
  final LearningSettingsViewModel viewModel;

  const AudioSettingsSection({super.key, required this.viewModel});

  /// Auto-read-aloud only enables when the device offers a known-good voice
  /// for the selected target language; otherwise the toggle stays off and the
  /// dialog points to where a qualifying voice can be found. See
  /// message-read-aloud.instructions.md.
  Future<bool> _onEnableReadAloud(BuildContext context) async {
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
        ...ToolSetting.audioSettings
            .where((setting) => setting != ToolSetting.audioIncomingMessages)
            .map(
              (setting) => ProfileSettingsSwitchListTile.adaptive(
                defaultValue: viewModel.getToolSetting(setting),
                title: setting.toolName(context),
                subtitle: setting.toolDescription(context),
                onChange: (v) => viewModel.updateToolSetting(setting, v),
              ),
            ),
        SwitchListTile.adaptive(
          value: viewModel.getToolSetting(ToolSetting.audioIncomingMessages),
          title: Text(ToolSetting.audioIncomingMessages.toolName(context)),
          subtitle: Text(
            ToolSetting.audioIncomingMessages.toolDescription(context),
          ),
          activeThumbColor: AppConfig.activeToggleColor,
          onChanged: (v) async {
            if (v) {
              final enabled = await _onEnableReadAloud(context);
              if (!enabled) return;
            }
            viewModel.updateToolSetting(ToolSetting.audioIncomingMessages, v);
          },
        ),
      ],
    );
  }
}
