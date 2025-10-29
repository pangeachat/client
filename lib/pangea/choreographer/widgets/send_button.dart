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
      if (controller.choreographer.firstIGCMatch != null) {
        OverlayUtil.showIGCMatch(
          controller.choreographer.firstIGCMatch!,
          controller.choreographer,
          context,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.choreographer,
      builder: (context, _) {
        return ValueListenableBuilder(
          valueListenable: controller.choreographer.textController,
          builder: (context, _, __) {
            return Container(
              height: 56,
              alignment: Alignment.center,
              child: IconButton(
                icon: const Icon(Icons.send_outlined),
                color: controller.choreographer.assistanceState
                    .stateColor(context),
                onPressed: controller.choreographer.isFetching
                    ? null
                    : () => _onPressed(context),
                tooltip: L10n.of(context).send,
              ),
            );
          },
        );
      },
    );
  }
}
