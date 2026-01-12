import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/common/widgets/card_header.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class DisableLanguageToolsPopup extends StatelessWidget {
  final String overlayId;

  const DisableLanguageToolsPopup({
    super.key,
    required this.overlayId,
  });

  Future<void> _disableLanguageTools() async {
    await MatrixState.pangeaController.userController.updateProfile(
      (profile) {
        profile.toolSettings.autoIGC = false;
        return profile;
      },
      waitForDataInSync: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CardHeader(L10n.of(context).disableLanguageToolsTitle),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            spacing: 12.0,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                L10n.of(context).disableLanguageToolsDesc,
                style: BotStyle.text(context),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await showFutureLoadingDialog(
                      context: context,
                      future: _disableLanguageTools,
                    );
                    MatrixState.pAnyState.closeOverlay(overlayId);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.primary.withAlpha(25),
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
