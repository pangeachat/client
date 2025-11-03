import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_ui_extension.dart';
import 'package:fluffychat/pangea/choreographer/enums/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/paywall_card.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import '../../../pages/chat/chat.dart';

class ChoreographerSendButton extends StatelessWidget {
  const ChoreographerSendButton({
    super.key,
    required this.controller,
  });
  final ChatController controller;

  Future<void> _onPressed(BuildContext context) async {
    controller.choreographer.onClickSend();
    try {
      await controller.choreographer.send();
    } on ShowPaywallException {
      PaywallCard.show(
        context,
        controller.choreographer.inputTransformTargetKey,
      );
    } on OpenMatchesException {
      if (controller.choreographer.firstOpenMatch != null) {
        if (controller.choreographer.firstOpenMatch!.updatedMatch.isITStart) {
          controller.choreographer
              .openIT(controller.choreographer.firstOpenMatch!);
        } else {
          OverlayUtil.showIGCMatch(
            controller.choreographer.firstOpenMatch!,
            controller.choreographer,
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
        controller.choreographer.textController,
        controller.choreographer.isFetching,
      ]),
      builder: (context, _) {
        return Container(
          height: 56,
          alignment: Alignment.center,
          child: IconButton(
            icon: const Icon(Icons.send_outlined),
            color: controller.choreographer.assistanceState
                .sendButtonColor(context),
            onPressed: controller.choreographer.isFetching.value
                ? null
                : () => _onPressed(context),
            tooltip: L10n.of(context).send,
          ),
        );
      },
    );
  }
}
