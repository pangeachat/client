import 'dart:developer';

import 'package:fluffychat/pangea/constants/language_constants.dart';
import 'package:fluffychat/pangea/controllers/language_list_controller.dart';
import 'package:fluffychat/pangea/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/models/language_model.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';

import '../../../config/themes.dart';
import '../../../widgets/matrix.dart';
import 'p_language_dropdown.dart';
import 'p_question_container.dart';

Future<void> pLanguageDialog(
  BuildContext parentContext,
  Function callback,
) async {
  final PangeaController pangeaController = MatrixState.pangeaController;
  //PTODO: if source language not set by user, default to languge from device settings
  final LanguageModel? userL1 = pangeaController.languageController.userL1;
  final LanguageModel? userL2 = pangeaController.languageController.userL2;
  final String systemLang = Localizations.localeOf(parentContext).languageCode;
  final LanguageModel systemLanguage = PangeaLanguage.byLangCode(systemLang);

  LanguageModel selectedSourceLanguage = systemLanguage;
  if (userL1 != null && userL1.langCode != LanguageKeys.unknownLanguage) {
    selectedSourceLanguage = userL1;
  }

  LanguageModel selectedTargetLanguage;
  if (userL2 != null && userL2.langCode != LanguageKeys.unknownLanguage) {
    selectedTargetLanguage = userL2;
  } else {
    selectedTargetLanguage = selectedSourceLanguage.langCode != 'en'
        ? PangeaLanguage.byLangCode('en')
        : PangeaLanguage.byLangCode('es');
  }

  return showDialog(
    useRootNavigator: false,
    context: parentContext,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: AlertDialog(
              title: Text(L10n.of(parentContext)!.updateLanguage),
              content: SizedBox(
                width: FluffyThemes.columnWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PQuestionContainer(
                      title: L10n.of(parentContext)!.whatIsYourBaseLanguage,
                    ),
                    PLanguageDropdown(
                      onChange: (p0) =>
                          setState(() => selectedSourceLanguage = p0),
                      initialLanguage: selectedSourceLanguage,
                      languages: pangeaController.pLanguageStore.baseOptions,
                    ),
                    PQuestionContainer(
                      title: L10n.of(parentContext)!.whatLanguageYouWantToLearn,
                    ),
                    PLanguageDropdown(
                      onChange: (p0) =>
                          setState(() => selectedTargetLanguage = p0),
                      initialLanguage: selectedTargetLanguage,
                      languages: pangeaController.pLanguageStore.targetOptions,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(L10n.of(parentContext)!.cancel),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
                TextButton(
                  onPressed: () {
                    selectedSourceLanguage.langCode !=
                            selectedTargetLanguage.langCode
                        ? showFutureLoadingDialog(
                            context: context,
                            future: () async {
                              try {
                                pangeaController.myAnalytics
                                    .sendLocalAnalyticsToAnalyticsRoom()
                                    .then((_) {
                                  pangeaController.userController.updateProfile(
                                    (profile) {
                                      profile.userSettings.sourceLanguage =
                                          selectedSourceLanguage.langCode;
                                      profile.userSettings.targetLanguage =
                                          selectedTargetLanguage.langCode;
                                      return profile;
                                    },
                                    waitForDataInSync: true,
                                  );
                                }).then((_) {
                                  // if the profile update is successful, reset cached analytics
                                  // data, since analytics data corresponds to the user's L2
                                  pangeaController.myAnalytics.dispose();
                                  pangeaController.analytics.dispose();

                                  pangeaController.myAnalytics.initialize();
                                  pangeaController.analytics.initialize();

                                  Navigator.pop(context);
                                });
                              } catch (err, s) {
                                debugger(when: kDebugMode);
                                ErrorHandler.logError(e: err, s: s);
                                rethrow;
                              } finally {
                                callback();
                              }
                            },
                          )
                        : ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                L10n.of(parentContext)!.noIdenticalLanguages,
                              ),
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                            ),
                          );
                  },
                  child: Text(L10n.of(parentContext)!.saveChanges),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
