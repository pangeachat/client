import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/language_level_dropdown.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/pangea/instructions/reset_instructions_list_tile.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/country_picker_tile.dart';
import 'package:fluffychat/pangea/learning_settings/gender_dropdown.dart';
import 'package:fluffychat/pangea/learning_settings/p_language_dropdown.dart';
import 'package:fluffychat/pangea/learning_settings/p_settings_switch_list_tile.dart';
import 'package:fluffychat/pangea/learning_settings/settings_learning.dart';
import 'package:fluffychat/pangea/learning_settings/tool_settings_enum.dart';
import 'package:fluffychat/pangea/learning_settings/voice_dropdown.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SettingsLearningView extends StatelessWidget {
  final SettingsLearningController controller;
  const SettingsLearningView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Matrix.of(context).client.onSync.stream.where((update) {
        return update.accountData != null &&
            update.accountData!.any(
              (event) => event.type == ModelKey.userProfile,
            );
      }),
      builder: (context, _) {
        final dialogContent = Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !controller.widget.isDialog,
            centerTitle: true,
            title: Text(L10n.of(context).learningSettings),
            leading: controller.widget.isDialog
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: controller.onSettingsClose,
                  )
                : null,
          ),
          body: ListTileTheme(
            iconColor: Theme.of(context).textTheme.bodyLarge!.color,
            child: MaxWidthBody(
              withScrolling: false,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: controller.scrollController,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32.0),
                        child: Column(
                          spacing: 16.0,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Column(
                                spacing: 16.0,
                                children: [
                                  PLanguageDropdown(
                                    onChange: (lang) =>
                                        controller.setSelectedLanguage(
                                          sourceLanguage: lang,
                                        ),
                                    initialLanguage:
                                        controller.selectedSourceLanguage ??
                                        LanguageModel.unknown,
                                    languages: MatrixState
                                        .pangeaController
                                        .pLanguageStore
                                        .baseOptions,
                                    isL2List: false,
                                    decorationText: L10n.of(
                                      context,
                                    ).myBaseLanguage,
                                    hasError:
                                        controller.languageMatchError != null,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                                  ),
                                  PLanguageDropdown(
                                    onChange: (lang) =>
                                        controller.setSelectedLanguage(
                                          targetLanguage: lang,
                                        ),
                                    initialLanguage:
                                        controller.selectedTargetLanguage,
                                    languages: MatrixState
                                        .pangeaController
                                        .pLanguageStore
                                        .targetOptions,
                                    isL2List: true,
                                    decorationText: L10n.of(
                                      context,
                                    ).iWantToLearn,
                                    error: controller.languageMatchError,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                                  ),
                                  if (controller.userL1?.langCodeShort ==
                                      controller.userL2?.langCodeShort)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                      ),
                                      child: Row(
                                        spacing: 8.0,
                                        children: [
                                          Icon(
                                            Icons.info_outlined,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          ),
                                          Flexible(
                                            child: Text(
                                              L10n.of(
                                                context,
                                              ).noIdenticalLanguages,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  LanguageLevelDropdown(
                                    initialLevel: controller.cefrLevel,
                                    onChanged: controller.setCefrLevel,
                                  ),
                                  VoiceDropdown(
                                    value: controller.selectedVoice,
                                    language: controller.selectedTargetLanguage,
                                    onChanged: controller.setVoice,
                                  ),
                                  CountryPickerDropdown(controller),
                                  GenderDropdown(
                                    initialGender: controller.gender,
                                    onChanged: controller.setGender,
                                  ),
                                ],
                              ),
                            ),
                            ...ToolSetting.values
                                .where((tool) => tool.isAvailableSetting)
                                .map(
                                  (toolSetting) => _ProfileSwitchTile(
                                    value: controller.getToolSetting(
                                      toolSetting,
                                    ),
                                    setting: toolSetting,
                                    onChanged: (v) {
                                      controller.updateToolSetting(
                                        toolSetting,
                                        v,
                                      );
                                      if (v &&
                                          toolSetting ==
                                              ToolSetting.enableTTS) {
                                        controller.showKeyboardSettingsDialog();
                                      }
                                    },
                                  ),
                                ),
                            SwitchListTile.adaptive(
                              value: controller.publicProfile,
                              onChanged: controller.setPublicProfile,
                              title: Text(L10n.of(context).publicProfileTitle),
                              subtitle: Text(
                                L10n.of(context).publicProfileDesc,
                              ),
                              activeThumbColor: AppConfig.activeToggleColor,
                            ),
                            ResetInstructionsListTile(controller: controller),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: controller.haveSettingsBeenChanged
                            ? controller.submit
                            : null,
                        child: Text(L10n.of(context).saveChanges),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (!controller.widget.isDialog) return dialogContent;
        return FullWidthDialog(
          dialogContent: dialogContent,
          maxWidth: 600,
          maxHeight: 800,
        );
      },
    );
  }
}

class _ProfileSwitchTile extends StatelessWidget {
  final bool value;
  final ToolSetting setting;
  final Function(bool) onChanged;

  const _ProfileSwitchTile({
    required this.value,
    required this.setting,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ProfileSettingsSwitchListTile.adaptive(
      defaultValue: value,
      title: setting.toolName(context),
      subtitle: setting.toolDescription(context),
      onChange: onChanged,
    );
  }
}
