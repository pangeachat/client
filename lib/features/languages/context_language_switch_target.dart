import 'package:flutter/material.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_switcher_sheet.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Wraps a content language chip with the tap-to-switch behavior every one
/// shares (profile.instructions.md, "Switching from context", point 6): the
/// activity start page's info row, a course's info chips, and a running
/// session's goal header. [builder] renders the chip itself and gets
/// [canSwitch] so it can tint accordingly; this widget owns whether that's
/// tappable and gives the whole thing a single accessible name — the
/// language's spoken name, "Switch to {language}" when there's a switch to
/// offer — replacing whatever semantics [builder]'s chip carries on its own
/// (several of these chips otherwise read only their abbreviated code).
///
/// [canSwitch] is false — and the built chip is left untappable — when
/// [contentLanguage] is already the learner's target language or their base
/// language (a switch there is refused, so there's nothing to offer). An
/// unresolved (null) [contentLanguage] is passed through entirely as
/// [builder] drew it, semantics included.
class ContextLanguageSwitchTarget extends StatelessWidget {
  final LanguageModel? contentLanguage;
  final Widget Function(BuildContext context, bool canSwitch) builder;

  const ContextLanguageSwitchTarget({
    required this.contentLanguage,
    required this.builder,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final userController = MatrixState.pangeaController.userController;
    // A completed switch fires languageStream (see UserController), which is
    // the only thing that can change canSwitch for an already-built chip —
    // without listening here, a chip stays tinted for the language the
    // learner just switched away from until something unrelated rebuilds it.
    return StreamBuilder<LanguageUpdate>(
      stream: userController.languageStream.stream,
      builder: (context, _) => _build(context, userController),
    );
  }

  Widget _build(BuildContext context, UserController userController) {
    final language = contentLanguage;
    final canSwitch =
        language != null &&
        UserController.canSwitchTo(
          language,
          targetLangCode: userController.userL2?.langCode,
          baseLangCode: userController.userL1?.langCode,
        );

    final chip = builder(context, canSwitch);
    // A resolved language always gets a proper spoken name here — several
    // callers' own chip otherwise reads only its abbreviated code — plus the
    // switch affordance when there's one to offer.
    if (language == null) return chip;

    final l10n = L10n.of(context);
    final label = canSwitch
        ? l10n.switchLanguageChipLabel(language.getDisplayName(l10n))
        : language.getDisplayName(l10n);

    return Semantics(
      button: canSwitch,
      label: label,
      excludeSemantics: true,
      child: canSwitch
          ? InkWell(
              onTap: () => LanguageSwitcherSheet.show(
                context,
                targetedLanguage: language,
              ),
              child: chip,
            )
          : chip,
    );
  }
}
