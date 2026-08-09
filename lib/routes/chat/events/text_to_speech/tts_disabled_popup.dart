import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/utils/bot_style.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/card_header.dart';

class TtsDisabledPopup extends StatelessWidget {
  const TtsDisabledPopup({super.key});

  static void show(BuildContext context, String targetID) {
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: Column(
        spacing: 12.0,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CardHeader(InstructionsEnum.ttsDisabled.title(L10n.of(context))),
          Padding(
            padding: const EdgeInsets.all(6.0),
            child: Text(
              InstructionsEnum.ttsDisabled.body(L10n.of(context)),
              style: BotStyle.text(context),
            ),
          ),
        ],
      ),
      displayDetails: PositionedOverlayDisplayDetails(
        maxHeight: 300,
        maxWidth: 300,
        transformTargetId: targetID,
        closePrevOverlay: false,
        overlayKey: InstructionsEnum.ttsDisabled.toString(),
        backDropToDismiss: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 12.0,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CardHeader(InstructionsEnum.ttsDisabled.title(L10n.of(context))),
        Padding(
          padding: const EdgeInsets.all(6.0),
          child: Text(
            InstructionsEnum.ttsDisabled.body(L10n.of(context)),
            style: BotStyle.text(context),
          ),
        ),
      ],
    );
  }
}
