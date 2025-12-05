import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
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
            title: Text(
              L10n.of(context).learningSettings,
            ),
            leading: controller.widget.isDialog
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: controller.onSettingsClose,
                  )
                : null,
          ),
          body: Form(
            key: controller.formKey,
            child: ListTileTheme(
              iconColor: Theme.of(context).textTheme.bodyLarge!.color,
              child: MaxWidthBody(
                withScrolling: false,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        controller: controller.scrollController,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
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
                                    languages: MatrixState.pangeaController
                                        .pLanguageStore.baseOptions,
                                    isL2List: false,
                                    decorationText:
                                        L10n.of(context).myBaseLanguage,
                                    hasError:
                                        controller.languageMatchError != null,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh,
                                  ),
                                  PLanguageDropdown(
                                    onChange: (lang) =>
                                        controller.setSelectedLanguage(
                                      targetLanguage: lang,
                                    ),
                                    initialLanguage:
                                        controller.selectedTargetLanguage,
                                    languages: MatrixState.pangeaController
                                        .pLanguageStore.targetOptions,
                                    isL2List: true,
                                    decorationText:
                                        L10n.of(context).iWantToLearn,
                                    error: controller.languageMatchError,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh,
                                  ),
                                  AnimatedSize(
                                    duration: FluffyThemes.animationDuration,
                                    curve: FluffyThemes.animationCurve,
                                    child: controller.userL1?.langCodeShort ==
                                            controller.userL2?.langCodeShort
                                        ? Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16.0,
                                            ),
                                            child: Row(
                                              spacing: 8.0,
                                              children: [
                                                Icon(
                                                  Icons.info_outlined,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error,
                                                ),
                                                Flexible(
                                                  child: Text(
                                                    L10n.of(context)
                                                        .noIdenticalLanguages,
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                  CountryPickerDropdown(controller),
                                  LanguageLevelDropdown(
                                    initialLevel: controller.cefrLevel,
                                    onChanged: controller.setCefrLevel,
                                  ),
                                  GenderDropdown(
                                    initialGender: controller.gender,
                                    onChanged: controller.setGender,
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.white54,
                                      ),
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      children: [
                                        ProfileSettingsSwitchListTile.adaptive(
                                          defaultValue:
                                              controller.getToolSetting(
                                            ToolSetting.autoIGC,
                                          ),
                                          title: ToolSetting.autoIGC
                                              .toolName(context),
                                          subtitle: ToolSetting.autoIGC
                                              .toolDescription(context),
                                          onChange: (bool value) =>
                                              controller.updateToolSetting(
                                            ToolSetting.autoIGC,
                                            value,
                                          ),
                                          enabled: true,
                                        ),
                                        ProfileSettingsSwitchListTile.adaptive(
                                          defaultValue:
                                              controller.getToolSetting(
                                            ToolSetting.enableAutocorrect,
                                          ),
                                          title: ToolSetting.enableAutocorrect
                                              .toolName(context),
                                          subtitle: ToolSetting
                                              .enableAutocorrect
                                              .toolDescription(context),
                                          onChange: (bool value) {
                                            controller.updateToolSetting(
                                              ToolSetting.enableAutocorrect,
                                              value,
                                            );
                                            if (value) {
                                              controller
                                                  .showKeyboardSettingsDialog();
                                            }
                                          },
                                          enabled: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                  for (final toolSetting
                                      in ToolSetting.values.where(
                                    (tool) =>
                                        tool.isAvailableSetting &&
                                        tool != ToolSetting.autoIGC &&
                                        tool != ToolSetting.enableAutocorrect,
                                  ))
                                    Column(
                                      children: [
                                        ProfileSettingsSwitchListTile.adaptive(
                                          defaultValue: controller
                                              .getToolSetting(toolSetting),
                                          title: toolSetting.toolName(context),
                                          subtitle: toolSetting ==
                                                      ToolSetting.enableTTS &&
                                                  !controller.isTTSSupported
                                              ? null
                                              : toolSetting
                                                  .toolDescription(context),
                                          onChange: (bool value) =>
                                              controller.updateToolSetting(
                                            toolSetting,
                                            value,
                                          ),
                                        ),
                                      ],
                                    ),
                                  SwitchListTile.adaptive(
                                    value: controller.publicProfile,
                                    onChanged: controller.setPublicProfile,
                                    title: Text(
                                      L10n.of(context).publicProfileTitle,
                                    ),
                                    subtitle: Text(
                                      L10n.of(context).publicProfileDesc,
                                    ),
                                    activeThumbColor:
                                        AppConfig.activeToggleColor,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  ResetInstructionsListTile(
                                    controller: controller,
                                  ),
                                ],
                              ),
                            ),
                          ],
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
