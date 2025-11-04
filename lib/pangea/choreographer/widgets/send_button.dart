import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_ui_extension.dart';
import 'package:fluffychat/pangea/choreographer/enums/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/paywall_card.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';

class ChoreographerSendButton extends StatelessWidget {
  final Choreographer choreographer;
  const ChoreographerSendButton({
    super.key,
    required this.choreographer,
  });

  Future<void> _onPressed(BuildContext context) async {
    choreographer.onClickSend();
    try {
      await choreographer.send();
    } on ShowPaywallException {
      PaywallCard.show(
        context,
        choreographer.inputTransformTargetKey,
      );
    } on OpenMatchesException {
      if (choreographer.firstOpenMatch != null) {
        if (choreographer.firstOpenMatch!.updatedMatch.isITStart) {
          choreographer.openIT(choreographer.firstOpenMatch!);
        } else {
          OverlayUtil.showIGCMatch(
            choreographer.firstOpenMatch!,
            choreographer,
            context,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        choreographer.textController,
        choreographer.isFetching,
      ]),
      builder: (context, _) {
        return Container(
          height: 56,
          alignment: Alignment.center,
          child: IconButton(
            icon: const Icon(Icons.send_outlined),
            color: choreographer.assistanceState.sendButtonColor(context),
            onPressed: choreographer.isFetching.value
                ? null
                : () => _onPressed(context),
            tooltip: L10n.of(context).send,
          ),
        );
      },
    );
  }
}
