import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/utils/bot_style.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/overlay/overlay_position.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/card_header.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class IdenticalLanguageException implements Exception {}

class MissingLanguageException implements Exception {}

class LanguageMismatchPopup extends StatelessWidget {
  final String message;
  final String overlayId;
  final LanguageModel targetLanguage;
  final VoidCallback onConfirm;

  const LanguageMismatchPopup({
    super.key,
    required this.message,
    required this.overlayId,
    required this.targetLanguage,
    required this.onConfirm,
  });

  static void show({
    required BuildContext context,
    required String targetId,
    required String message,
    required LanguageModel targetLanguage,
    required VoidCallback onConfirm,
  }) {
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: LanguageMismatchPopup(
        message: message,
        overlayId: 'language_mismatch_popup',
        onConfirm: onConfirm,
        targetLanguage: targetLanguage,
      ),
      displayDetails: PositionedOverlayDisplayDetails(
        maxHeight: 325,
        maxWidth: 325,
        transformTargetId: targetId,
        overlayKey: 'language_mismatch_popup',
      ),
      overlayPosition: OverlayPosition.above,
    );
  }

  Future<void> _updateLanguage() async {
    await MatrixState.pangeaController.userController.updateProfile((profile) {
      final targetLangShort = targetLanguage.langCodeShort;
      final baseLangShort = profile.userSettings.sourceLanguage
          ?.split('-')
          .first;

      if (baseLangShort != null && targetLangShort == baseLangShort) {
        throw IdenticalLanguageException();
      }

      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: targetLanguage.langCode,
        ),
      );
    }, waitForDataInSync: true);
    onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CardHeader(L10n.of(context).languageMismatchTitle),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            spacing: 12.0,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                message,
                style: BotStyle.text(context),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await showFutureLoadingDialog(
                      context: context,
                      future: _updateLanguage,
                    );
                    MatrixState.pAnyState.closeOverlay(overlayId);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withAlpha(25),
                  ),
                  child: Text(L10n.of(context).confirm),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
