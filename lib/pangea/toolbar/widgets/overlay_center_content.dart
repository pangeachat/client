import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message_reactions.dart';
import 'package:fluffychat/pangea/toolbar/enums/reading_assistance_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/measure_render_box.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/overlay_message.dart';
import 'package:fluffychat/widgets/matrix.dart';

class OverlayCenterContent extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? prevEvent;

  final MessageOverlayController overlayController;
  final ChatController chatController;

  final Animation<Size>? sizeAnimation;
  final void Function(RenderBox)? onChangeMessageSize;

  final double? messageHeight;
  final double? messageWidth;

  final bool hasReactions;

  final bool isTransitionAnimation;
  final ReadingAssistanceMode? readingAssistanceMode;

  const OverlayCenterContent({
    required this.event,
    required this.messageHeight,
    required this.messageWidth,
    required this.overlayController,
    required this.chatController,
    required this.nextEvent,
    required this.prevEvent,
    required this.hasReactions,
    this.onChangeMessageSize,
    this.sizeAnimation,
    this.isTransitionAnimation = false,
    this.readingAssistanceMode,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !isTransitionAnimation &&
          readingAssistanceMode != ReadingAssistanceMode.practiceMode,
      child: Container(
        constraints: BoxConstraints(maxWidth: overlayController.maxWidth),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: event.senderId == event.room.client.userID
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              MeasureRenderBox(
                onChange: onChangeMessageSize,
                child: OverlayMessage(
                  key: isTransitionAnimation
                      ? MatrixState.pAnyState
                          .layerLinkAndKey('overlay_message_${event.eventId}')
                          .key
                      : null,
                  event,
                  immersionMode: chatController.choreographer.immersionMode,
                  controller: chatController,
                  overlayController: overlayController,
                  nextEvent: nextEvent,
                  previousEvent: prevEvent,
                  timeline: chatController.timeline!,
                  sizeAnimation: sizeAnimation,
                  // there's a split seconds between when the transition animation starts and
                  // when the sizeAnimation is set when the original dimensions need to be enforced
                  messageWidth: (sizeAnimation == null && isTransitionAnimation)
                      ? messageWidth
                      : null,
                  messageHeight:
                      (sizeAnimation == null && isTransitionAnimation)
                          ? messageHeight
                          : null,
                  isTransitionAnimation: isTransitionAnimation,
                  readingAssistanceMode: readingAssistanceMode,
                ),
              ),
              if (hasReactions)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    height: 20,
                    child: MessageReactions(
                      event,
                      chatController.timeline!,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
