import 'package:flutter/material.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

/// The app's menus and buttons follow the base language, so a new base
/// language that would switch them is confirmed first (#9410).
class BaseLanguageChangeDialog {
  /// Resolves true only when the learner taps Change.
  static Future<bool> confirm(
    BuildContext context,
    LanguageModel language,
  ) async {
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.changeBaseLanguageTitle,
      message: l10n.changeBaseLanguageDesc(language.getDisplayName(l10n)),
      okLabel: l10n.change,
    );
    return result == OkCancelResult.ok;
  }
}
