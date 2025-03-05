import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';

class MessageModeLockedCard extends StatelessWidget {
  final MessageOverlayController controller;

  const MessageModeLockedCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
          if(!InstructionsEnum.completeActivitiesToUnlock.isToggledOff)
          ...[const SizedBox(height: 8),
          const InstructionsInlineTooltip(instructionsEnum: InstructionsEnum.completeActivitiesToUnlock),],
        ],
      ),
    );
  }
}
