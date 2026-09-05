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
  /// for the selected target language. The gate is re-run at tap time because
  /// the page-open answer can be stale (#8282); when it now fails, the dialog
  /// points to where a qualifying voice can be found and the toggles fall back
  /// to their disabled state. See message-read-aloud.instructions.md.
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
    // Without a known-good voice the message-audio settings cannot do
    // anything, so those toggles render disabled and a single note above them
    // carries the explanation plus the toolbar alternative (#8664). See
    // message-read-aloud.instructions.md.
    final hasVoice = viewModel.hasKnownGoodVoice;
    final language = viewModel.selectedTargetLanguage?.displayName;
    // Read from the PENDING profile, not the saved one, so turning choice
    // audio off releases Listen First in the same breath rather than after a
    // save.
    final hasChoiceAudio = viewModel.getToolSetting(ToolSetting.audioChoices);
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
            .where(
              (setting) =>
                  !setting.isMessageAudioSetting &&
                  !setting.requiresChoiceAudio,
            )
            .map(
              (setting) => ProfileSettingsSwitchListTile.adaptive(
                defaultValue: viewModel.getToolSetting(setting),
                title: setting.toolName(context),
                subtitle: setting.toolDescription(context),
                onChange: (v) => viewModel.updateToolSetting(setting, v),
              ),
            ),
        // Listen First sequences choice audio, so with that audio off it is
        // a mode that plays nothing. Offered as unavailable, with the reason,
        // rather than as a switch that flips and changes nothing.
        ...ToolSetting.audioSettings
            .where((s) => s.requiresChoiceAudio)
            .map(
              (setting) => SwitchListTile.adaptive(
                value: hasChoiceAudio && viewModel.getToolSetting(setting),
                title: Text(setting.toolName(context)),
                subtitle: Text(
                  hasChoiceAudio
                      ? setting.toolDescription(context)
                      : L10n.of(context).listenFirstNeedsChoiceAudio,
                ),
                activeThumbColor: AppConfig.activeToggleColor,
                onChanged: !hasChoiceAudio
                    ? null
                    : (v) => viewModel.updateToolSetting(setting, v),
              ),
            ),
        if (!hasVoice && language != null)
          ListTile(
            subtitle: Text(L10n.of(context).readAloudNoVoiceNote(language)),
          ),
        ...ToolSetting.audioSettings
            .where((setting) => setting.isMessageAudioSetting)
            .map(
              (setting) => SwitchListTile.adaptive(
                value: viewModel.getToolSetting(setting),
                title: Text(setting.toolName(context)),
                subtitle: Text(setting.toolDescription(context)),
                activeThumbColor: AppConfig.activeToggleColor,
                onChanged: !hasVoice
                    ? null
                    : (v) async {
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
