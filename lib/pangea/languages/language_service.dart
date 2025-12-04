// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import 'package:universal_io/io.dart';

import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../learning_settings/p_language_dialog.dart';

class LanguageService {
  static void showDialogOnEmptyLanguage(
    BuildContext context,
    Function callback,
  ) {
    if (!MatrixState.pangeaController.userController.languagesSet) {
      pLanguageDialog(context, callback);
    }
  }

  static LanguageModel? get systemLanguage {
    if (Platform.localeName.length < 2) return null;
    final String systemLang = Platform.localeName.substring(0, 2);
    return PLanguageStore.byLangCode(systemLang);
  }
}
