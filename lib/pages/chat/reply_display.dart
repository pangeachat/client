import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import '../../config/themes.dart';
import 'chat.dart';
import 'events/reply_content.dart';

class ReplyDisplay extends StatelessWidget {
  final ChatController controller;
  const ReplyDisplay(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // #Pangea
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.replyEvent,
        controller.editEvent,
      ]),
      builder: (context, _) {
        final editEvent = controller.editEvent.value;
        final replyEvent = controller.replyEvent.value;
        // Pangea#
        return AnimatedContainer(
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          // #Pangea
          // height: controller.editEvent != null || controller.replyEvent != null
          height: editEvent != null || replyEvent != null
              // Pangea#
              ? 56
              : 0,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(color: theme.colorScheme.onInverseSurface),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: L10n.of(context).close,
                icon: const Icon(Icons.close),
                onPressed: controller.cancelReplyEventAction,
              ),
              Expanded(
                // #Pangea
                // child: controller.replyEvent != null
                child: replyEvent != null
                    // Pangea#
                    ? ReplyContent(
                        // #Pangea
                        // controller.replyEvent,
                        replyEvent,
                        // Pangea#
                        timeline: controller.timeline!,
                      )
                    : _EditContent(
                        // #Pangea
                        // controller.editEvent?.getDisplayEvent(controller.timeline!),
                        editEvent?.getDisplayEvent(controller.timeline!),
                        // Pangea#
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditContent extends StatelessWidget {
  final Event? event;

  const _EditContent(this.event);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = this.event;
    if (event == null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: <Widget>[
        Icon(Icons.edit, color: theme.colorScheme.primary),
        Container(width: 15.0),
        // #Pangea
        // Text(
        //   event.calcLocalizedBodyFallback(
        //     MatrixLocals(L10n.of(context)),
        //     withSenderNamePrefix: false,
        //     hideReply: true,
        //   ),
        //   overflow: TextOverflow.ellipsis,
        //   maxLines: 1,
        //   style: TextStyle(color: theme.textTheme.bodyMedium!.color),
        // ),
        Flexible(
          child: Text(
            textScaler: TextScaler.noScaling,
            event.calcLocalizedBodyFallback(
              MatrixLocals(L10n.of(context)),
              withSenderNamePrefix: false,
              hideReply: true,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(color: theme.textTheme.bodyMedium!.color),
          ),
        ),
        // Pangea#
      ],
    );
  }
}
