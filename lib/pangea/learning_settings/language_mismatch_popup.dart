import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/common/widgets/card_header.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class IdenticalLanguageException implements Exception {}

class LanguageMismatchPopup extends StatelessWidget {
  final String message;
  final String overlayId;
  final String targetLanguage;
  final VoidCallback onConfirm;

  const LanguageMismatchPopup({
    super.key,
    required this.message,
    required this.overlayId,
    required this.targetLanguage,
    required this.onConfirm,
  });

  Future<void> _updateLanguage() async {
    await MatrixState.pangeaController.userController.updateProfile((profile) {
      profile.userSettings.targetLanguage = targetLanguage;
      return profile;
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
