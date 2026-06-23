// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import 'package:universal_io/io.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_language_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LanguageService {
  static Future<void> showDialogOnEmptyLanguage(BuildContext context) async {
    if (!MatrixState.pangeaController.userController.languagesSet) {
      final l1 = MatrixState.pangeaController.userController.userL1;
      final l2 = MatrixState.pangeaController.userController.userL2;
      await showDialog(
        context: context,
        builder: (context) =>
            PLanguageDialog(initialBaseLanguage: l1, initialTargetLanguage: l2),
        barrierDismissible: false,
      );
    }
  }

  static LanguageModel? get systemLanguage {
    if (Platform.localeName.length < 2) return null;
    final String systemLang = Platform.localeName.substring(0, 2);
    return PLanguageStore.byLangCode(systemLang);
  }
}
