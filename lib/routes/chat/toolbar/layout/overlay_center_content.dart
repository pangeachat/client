import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/routes/chat/pangea_message_reactions.dart';
import 'package:fluffychat/routes/chat/toolbar/layout/measure_render_box.dart';
import 'package:fluffychat/routes/chat/toolbar/layout/overlay_message.dart';
import 'package:fluffychat/routes/chat/toolbar/layout/reading_assistance_mode_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/message_selection_overlay.dart';
import 'package:fluffychat/routes/chat/toolbar/message_toolbar_host.dart';

class OverlayCenterContent extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? prevEvent;

  final MessageOverlayController overlayController;
  final MessageToolbarHost host;

  final Animation<Size>? sizeAnimation;
  final void Function(RenderBox)? onChangeMessageSize;

  final double? messageHeight;
  final double? messageWidth;

  final bool hasReactions;
  final ValueNotifier<double?> reactionsWidth;

  final bool isTransitionAnimation;
  final ReadingAssistanceMode? readingAssistanceMode;

  final String overlayKey;
  final bool useTokenKeys;

  const OverlayCenterContent({
    required this.event,
    required this.overlayKey,
    this.messageHeight,
    this.messageWidth,
    required this.overlayController,
    required this.host,
    required this.nextEvent,
    required this.prevEvent,
    required this.hasReactions,
    required this.reactionsWidth,
    this.onChangeMessageSize,
    this.sizeAnimation,
    this.isTransitionAnimation = false,
    this.readingAssistanceMode,
    this.useTokenKeys = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ownMessage = event.senderId == event.room.client.userID;
    return IgnorePointer(
      ignoring:
          !isTransitionAnimation &&
          readingAssistanceMode != ReadingAssistanceMode.practiceMode,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: FluffyThemes.maxTimelineWidth,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: event.senderId == event.room.client.userID
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              CompositedTransformTarget(
                link: overlayController.overlayMessageLayerLink.link,
                child: MeasureRenderBox(
                  onChange: onChangeMessageSize,
                  child: OverlayMessage(
                    overlayKey: overlayKey,
                    event,
                    controller: host,
                    overlayController: overlayController,
                    nextEvent: nextEvent,
                    previousEvent: prevEvent,
                    timeline: host.timeline!,
                    sizeAnimation: sizeAnimation,
                    // there's a split seconds between when the transition animation starts and
                    // when the sizeAnimation is set when the original dimensions need to be enforced
                    messageWidth: messageWidth,
                    messageHeight: messageHeight,
                    isTransitionAnimation: isTransitionAnimation,
                    readingAssistanceMode: readingAssistanceMode,
                    useTokenKeys: useTokenKeys,
                    canRefresh:
                        (event.eventId ==
                            host.chatController?.refreshEventID) &&
                        (readingAssistanceMode !=
                            ReadingAssistanceMode.practiceMode),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: 4.0,
                  left: ownMessage ? 0.0 : 4.0,
                ),
                child: ValueListenableBuilder(
                  valueListenable: reactionsWidth,
                  builder: (context, width, _) => PangeaMessageReactions(
                    event,
                    host.timeline!,
                    host,
                    width: width != null && width > 0 ? width : null,
                    enabled: !event.room.isActivityFinished,
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
