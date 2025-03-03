import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:app_settings/app_settings.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/language_level_dropdown.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/pages/settings_learning.dart';
import 'package:fluffychat/pangea/learning_settings/widgets/country_picker_tile.dart';
import 'package:fluffychat/pangea/learning_settings/widgets/p_language_dropdown.dart';
import 'package:fluffychat/pangea/learning_settings/widgets/p_settings_switch_list_tile.dart';
import 'package:fluffychat/pangea/spaces/models/space_model.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'dart:io'; 
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html; 


class SettingsLearningView extends StatelessWidget {
  final SettingsLearningController controller;
  const SettingsLearningView(this.controller, {super.key});

  void _showKeyboardSettingsDialog(BuildContext context) {
    String description;
    String buttonText;
    VoidCallback buttonAction;

    if (kIsWeb) {
      // Detect platform using userAgent for web
      final userAgent = html.window.navigator.userAgent.toLowerCase();
      if (userAgent.contains('mac') || userAgent.contains('iphone') || userAgent.contains('ipad')) {
        description = L10n.of(context).enableAutocorrectPopUpDescription;
        buttonText = 'Settings';
        buttonAction = () {
          AppSettings.openAppSettings();
        };
      } else if (userAgent.contains('android') || userAgent.contains('windows')) {
        description = L10n.of(context).downloadGboardDescription;
        buttonText = 'Download Gboard';
        buttonAction = () {
          launchUrlString('https://play.google.com/store/apps/details?id=com.google.android.inputmethod.latin');
        };
      } else {
        description = ''; // Default
        buttonText = 'OK';
        buttonAction = () {
          Navigator.of(context).pop();
        };
      }
    } else {
      if (Platform.isIOS || Platform.isMacOS) {
        description = L10n.of(context).enableAutocorrectPopUpDescription;
        buttonText = 'Settings';
        buttonAction = () {
          AppSettings.openAppSettings();
        };
      } else if (Platform.isAndroid || Platform.isWindows) {
        description = L10n.of(context).downloadGboardDescription;
        buttonText = 'Download Gboard';
        buttonAction = () {
          launchUrlString('https://play.google.com/store/apps/details?id=com.google.android.inputmethod.latin');
        };
      } else {
        description = 'unfortunately your platform is not currently supported for this feature. Stay tuned for further development!'; // Default
        buttonText = 'OK';
        buttonAction = () {
          Navigator.of(context).pop();
        };
      }
    }

    showAdaptiveDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(L10n.of(context).enableAutocorrectWarning),
          content: Text(description),
          actions: [
            TextButton(
              child: Text(L10n.of(context).cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(buttonText),
              onPressed: buttonAction,
            ),
            TextButton(
              child: const Text('Already Enabled'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

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
            centerTitle: true,
            title: Text(
              L10n.of(context).learningSettings,
            ),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: Navigator.of(context).pop,
            ),
          ),
          body: ListTileTheme(
            iconColor: Theme.of(context).textTheme.bodyLarge!.color,
            child: Form(
              key: controller.formKey,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 8.0,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
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
                                decorationText: L10n.of(context).myBaseLanguage,
                                hasError: controller.languageMatchError != null,
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
                                decorationText: L10n.of(context).iWantToLearn,
                                error: controller.languageMatchError,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                              ),
                              CountryPickerDropdown(controller),
                              LanguageLevelDropdown(
                                initialLevel: controller.cefrLevel,
                                onChanged: controller.setCefrLevel,
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
                                      defaultValue: controller
                                          .getToolSetting(ToolSetting.autoIGC), 
                                      title: ToolSetting.autoIGC.toolName(context),
                                      subtitle: ToolSetting.autoIGC.toolDescription(context),
                                      onChange: (bool value) =>
                                          controller.updateToolSetting(
                                        ToolSetting.autoIGC,
                                        value,
                                      ),
                                      enabled: true,
                                    ),
                                    ProfileSettingsSwitchListTile.adaptive(
                                      defaultValue: controller
                                          .getToolSetting(ToolSetting.enableAutocorrect), 
                                      title: ToolSetting.enableAutocorrect.toolName(context),
                                      subtitle: ToolSetting.enableAutocorrect.toolDescription(context),
                                      onChange: (bool value) {
                                        controller.updateToolSetting(
                                          ToolSetting.enableAutocorrect,
                                          value,
                                        );
                                        if (value) {
                                          _showKeyboardSettingsDialog(context);
                                        }
                                      },
                                      enabled: true,
                                    ),
                                  ],
                                ),
                              ),
                              for (final toolSetting in ToolSetting.values
                                  .where((tool) => tool.isAvailableSetting && tool != ToolSetting.autoIGC && tool != ToolSetting.enableAutocorrect))
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
                                      enabled:
                                          toolSetting == ToolSetting.enableTTS
                                              ? controller.isTTSSupported
                                              : true,
                                    ),
                                    if (toolSetting == ToolSetting.enableTTS &&
                                        !controller.isTTSSupported)
                                      Row(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 16.0,
                                            ),
                                            child: Icon(
                                              Icons.info_outlined,
                                              color: Theme.of(context)
                                                  .disabledColor,
                                            ),
                                          ),
                                          Flexible(
                                            child: RichText(
                                              text: TextSpan(
                                                text: L10n.of(context)
                                                    .couldNotFindTTS,
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .disabledColor,
                                                ),
                                                children: [
                                                  if (PlatformInfos.isWindows ||
                                                      PlatformInfos.isAndroid)
                                                    TextSpan(
                                                      text: L10n.of(context)
                                                          .ttsInstructionsHyperlink,
                                                      style: const TextStyle(
                                                        color: Colors.blue,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                      ),
                                                      recognizer:
                                                          TapGestureRecognizer()
                                                            ..onTap = () {
                                                              launchUrlString(
                                                                PlatformInfos
                                                                        .isWindows
                                                                    ? AppConfig
                                                                        .windowsTTSDownloadInstructions
                                                                    : AppConfig
                                                                        .androidTTSDownloadInstructions,
                                                              );
                                                            },
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
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
                                activeColor: AppConfig.activeToggleColor,
                                contentPadding: EdgeInsets.zero,
                              ),
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
                          onPressed: controller.submit,
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

        return FullWidthDialog(
          dialogContent: dialogContent,
          maxWidth: 600,
          maxHeight: 800,
        );
      },
    );
  }
}