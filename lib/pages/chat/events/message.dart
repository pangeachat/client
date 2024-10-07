import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/pages/games/story_game/game_chat.dart';
import 'package:fluffychat/pangea/utils/any_state_holder.dart';
import 'package:fluffychat/pangea/widgets/chat/game_state_view.dart';
import 'package:fluffychat/pangea/widgets/chat/message_buttons.dart';
import 'package:fluffychat/pangea/widgets/chat/message_selection_overlay.dart';
import 'package:fluffychat/pangea/widgets/chat/message_sent_by.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

import '../../../config/app_config.dart';
import 'message_content.dart';
import 'message_reactions.dart';
import 'reply_content.dart';
import 'state_message.dart';
import 'verification_request_content.dart';

class Message extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? previousEvent;
  final bool displayReadMarker;
  final void Function(Event) onSelect;
  final void Function(Event) onAvatarTab;
  final void Function(Event) onInfoTab;
  final void Function(String) scrollToEventId;
  final void Function() onSwipe;
  final bool longPressSelect;
  final bool selected;
  final Timeline timeline;
  final bool highlightMarker;
  final bool animateIn;
  final void Function()? resetAnimateIn;
  // #Pangea
  final bool immersionMode;
  final ChatController controller;
  final MessageOverlayController? overlayController;
  // Pangea#
  final Color? avatarPresenceBackgroundColor;

  const Message(
    this.event, {
    this.nextEvent,
    this.previousEvent,
    this.displayReadMarker = false,
    this.longPressSelect = false,
    required this.onSelect,
    required this.onInfoTab,
    required this.onAvatarTab,
    required this.scrollToEventId,
    required this.onSwipe,
    this.selected = false,
    required this.timeline,
    this.highlightMarker = false,
    this.animateIn = false,
    this.resetAnimateIn,
    this.avatarPresenceBackgroundColor,
    // #Pangea
    required this.immersionMode,
    required this.controller,
    this.overlayController,
    // Pangea#
    super.key,
  });

  // #Pangea
  void showToolbar(PangeaMessageEvent? pangeaMessageEvent) {
    // if overlayController is not null, the message is already in overlay mode
    if (pangeaMessageEvent != null && overlayController == null) {
      controller.showToolbar(
        pangeaMessageEvent,
        nextEvent: nextEvent,
        prevEvent: previousEvent,
      );
    }
  }
  // Pangea#

  @override
  Widget build(BuildContext context) {
    // #Pangea
    PangeaMessageEvent? pangeaMessageEvent;
    if (event.type == EventTypes.Message) {
      pangeaMessageEvent = PangeaMessageEvent(
        event: event,
        timeline: timeline,
        ownMessage: event.senderId == Matrix.of(context).client.userID,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.pangeaEditingEvent?.eventId == event.eventId) {
        pangeaMessageEvent?.updateLatestEdit();
        controller.clearEditingEvent();
      }
    });

    if (event.type == PangeaEventTypes.storyGame) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.columnWidth * 1.25,
          ),
          child: GameStateView(controller.room),
        ),
      );
    }
    // Pangea#
    final theme = Theme.of(context);

    if (!{
      EventTypes.Message,
      EventTypes.Sticker,
      EventTypes.Encrypted,
      EventTypes.CallInvite,
    }.contains(event.type)) {
      if (event.type.startsWith('m.call.')) {
        return const SizedBox.shrink();
      }
      return StateMessage(event);
    }

    if (event.type == EventTypes.Message &&
        event.messageType == EventTypes.KeyVerificationRequest) {
      return VerificationRequestContent(event: event, timeline: timeline);
    }

    final client = Matrix.of(context).client;
    // #Pangea
    // final ownMessage = event.senderId == client.userID;
    final ownMessage = controller.isStoryGameMode
        ? controller.storyGameAlignment(event) == Alignment.topRight
        : event.senderId == client.userID;
    // Pangea#

    // #Pangea
    // final alignment = ownMessage ? Alignment.topRight : Alignment.topLeft;
    final alignment = controller.storyGameAlignment(event);
    // Pangea#

    // ignore: deprecated_member_use
    var color = theme.colorScheme.surfaceVariant;
    final displayTime = event.type == EventTypes.RoomCreate ||
        nextEvent == null ||
        !event.originServerTs.sameEnvironment(nextEvent!.originServerTs);
    final nextEventSameSender =
        // #Pangea
        controller.isStoryGameMode
            ? controller.storyGameNextEventSameSender(event, nextEvent)
            :
            // Pangea#
            nextEvent != null &&
                {
                  EventTypes.Message,
                  EventTypes.Sticker,
                  EventTypes.Encrypted,
                }.contains(nextEvent!.type) &&
                nextEvent!.senderId == event.senderId &&
                !displayTime;

    final previousEventSameSender =
        // #Pangea
        controller.isStoryGameMode
            ? controller.storyGamePreviousEventSameSender(event, previousEvent)
            :
            // Pangea#
            previousEvent != null &&
                {
                  EventTypes.Message,
                  EventTypes.Sticker,
                  EventTypes.Encrypted,
                }.contains(previousEvent!.type) &&
                previousEvent!.senderId == event.senderId &&
                previousEvent!.originServerTs
                    .sameEnvironment(event.originServerTs);

    final textColor =
        ownMessage ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final rowMainAxisAlignment =
        ownMessage ? MainAxisAlignment.end : MainAxisAlignment.start;

    final displayEvent = event.getDisplayEvent(timeline);
    const hardCorner = Radius.circular(4);
    const roundedCorner = Radius.circular(AppConfig.borderRadius);
    final borderRadius =
        // #Pangea
        controller.isStoryGameMode
            ? controller.storyGameBorderRadius(
                event,
                nextEvent,
                previousEventSameSender,
              )
            :
            // Pangea#
            BorderRadius.only(
                topLeft: !ownMessage && nextEventSameSender
                    ? hardCorner
                    : roundedCorner,
                topRight: ownMessage && nextEventSameSender
                    ? hardCorner
                    : roundedCorner,
                bottomLeft: !ownMessage && previousEventSameSender
                    ? hardCorner
                    : roundedCorner,
                bottomRight: ownMessage && previousEventSameSender
                    ? hardCorner
                    : roundedCorner,
              );
    final noBubble = {
          MessageTypes.Video,
          MessageTypes.Image,
          MessageTypes.Sticker,
        }.contains(event.messageType) &&
        !event.redacted;
    final noPadding = {
      MessageTypes.File,
      MessageTypes.Audio,
    }.contains(event.messageType);

    if (ownMessage) {
      color = displayEvent.status.isError
          ? Colors.redAccent
          : theme.colorScheme.primary;
    }

    final resetAnimateIn = this.resetAnimateIn;
    var animateIn = this.animateIn;

    final row = StatefulBuilder(
      builder: (context, setState) {
        if (animateIn && resetAnimateIn != null) {
          WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
            animateIn = false;
            setState(resetAnimateIn);
          });
        }
        return AnimatedSize(
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          clipBehavior: Clip.none,
          alignment: ownMessage ? Alignment.bottomRight : Alignment.bottomLeft,
          child: animateIn
              ? const SizedBox(height: 0, width: double.infinity)
              : Stack(
                  children: [
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: InkWell(
                        // #Pangea
                        onTap: controller.clearSelectedEvents,
                        // onTap: () => onSelect(event),
                        // onLongPress: () => onSelect(event),
                        // Pangea#
                        borderRadius:
                            BorderRadius.circular(AppConfig.borderRadius / 2),
                        child: Material(
                          borderRadius:
                              BorderRadius.circular(AppConfig.borderRadius / 2),
                          color: selected
                              ? theme.colorScheme.secondaryContainer
                                  .withAlpha(100)
                              : highlightMarker
                                  ? theme.colorScheme.tertiaryContainer
                                      .withAlpha(100)
                                  : Colors.transparent,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: rowMainAxisAlignment,
                      children: [
                        // #Pangea
                        if (controller.isStoryGameMode &&
                            overlayController == null)
                          alignment == Alignment.topLeft &&
                                  overlayController == null
                              ? controller.storyGameAvatar(
                                  event,
                                  nextEvent,
                                )
                              : const SizedBox(
                                  height: Avatar.defaultSize,
                                  width: Avatar.defaultSize,
                                )

                        // if (longPressSelect)
                        //   SizedBox(
                        //     height: 32,
                        //     width: Avatar.defaultSize,
                        //     child: Checkbox.adaptive(
                        //       value: selected,
                        //       shape: const CircleBorder(),
                        //       onChanged: (_) => onSelect(event),
                        //     ),
                        //   )
                        // else if (nextEventSameSender || ownMessage)
                        else if (nextEventSameSender ||
                            ownMessage ||
                            overlayController != null)
                          // Pangea#
                          SizedBox(
                            width: Avatar.defaultSize,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: event.status == EventStatus.error
                                    ? const Icon(
                                        Icons.error,
                                        color: Colors.red,
                                      )
                                    : event.fileSendingStatus != null
                                        ? const CircularProgressIndicator
                                            .adaptive(
                                            strokeWidth: 1,
                                          )
                                        : null,
                              ),
                            ),
                          )
                        else
                          FutureBuilder<User?>(
                            future: event.fetchSenderUser(),
                            builder: (context, snapshot) {
                              final user = snapshot.data ??
                                  event.senderFromMemoryOrFallback;
                              return Avatar(
                                mxContent: user.avatarUrl,
                                name: user.calcDisplayname(),
                                presenceUserId: user.stateKey,
                                presenceBackgroundColor:
                                    avatarPresenceBackgroundColor,
                                onTap: () => onAvatarTab(event),
                              );
                            },
                          ),
                        Expanded(
                          child: Column(
                            // #Pangea
                            // crossAxisAlignment: CrossAxisAlignment.start,
                            crossAxisAlignment:
                                controller.storyGameCrossAxisAlignment(event),
                            // Pangea#
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // #Pangea
                              // if (!nextEventSameSender)
                              if (!nextEventSameSender &&
                                  overlayController == null)
                                // Pangea#
                                Padding(
                                  padding: const EdgeInsets.only(
                                    // #Pangea
                                    right: 8.0,
                                    // Pangea#
                                    left: 8.0,
                                    bottom: 4,
                                  ),
                                  // #Pangea
                                  // child: ownMessage || event.room.isDirectChat
                                  child: (ownMessage ||
                                              event.room.isDirectChat) &&
                                          !controller.isStoryGameMode
                                      // Pangea#
                                      ? const SizedBox(height: 12)
                                      : FutureBuilder<User?>(
                                          future: event.fetchSenderUser(),
                                          builder: (context, snapshot) {
                                            // #Pangea
                                            String displayname;
                                            if (!controller.isStoryGameMode) {
                                              // Pangea#
                                              displayname = snapshot.data
                                                      ?.calcDisplayname() ??
                                                  event
                                                      .senderFromMemoryOrFallback
                                                      .calcDisplayname();
                                              // #Pangea
                                            } else {
                                              displayname = controller
                                                  .storyGameDisplayName(
                                                event,
                                              );
                                            }
                                            // Pangea#
                                            return Text(
                                              displayname,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: (theme.brightness ==
                                                        Brightness.light
                                                    ? displayname.color
                                                    : displayname
                                                        .lightColorText),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            );
                                          },
                                        ),
                                ),
                              Container(
                                alignment: alignment,
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  // #Pangea
                                  right: 8,
                                  // Pangea#
                                ),
                                child: GestureDetector(
                                  // #Pangea
                                  onTap: () => showToolbar(pangeaMessageEvent),
                                  onLongPress: () =>
                                      showToolbar(pangeaMessageEvent),
                                  // onLongPress: longPressSelect
                                  //     ? null
                                  //     : () {
                                  //         HapticFeedback.heavyImpact();
                                  //         onSelect(event);
                                  //       },
                                  // Pangea#
                                  child: AnimatedOpacity(
                                    opacity: animateIn
                                        ? 0
                                        : event.redacted ||
                                                event.messageType ==
                                                    MessageTypes.BadEncrypted ||
                                                event.status.isSending
                                            ? 0.5
                                            : 1,
                                    duration: FluffyThemes.animationDuration,
                                    curve: FluffyThemes.animationCurve,
                                    child: Material(
                                      color:
                                          noBubble ? Colors.transparent : color,
                                      clipBehavior: Clip.antiAlias,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: borderRadius,
                                      ),
                                      // #Pangea
                                      child: CompositedTransformTarget(
                                        link: overlayController != null
                                            ? LayerLinkAndKey('overlay_msg')
                                                .link
                                            : MatrixState.pAnyState
                                                .layerLinkAndKey(event.eventId)
                                                .link,
                                        child: Container(
                                          key: overlayController != null
                                              ? LayerLinkAndKey('overlay_msg')
                                                  .key
                                              : MatrixState.pAnyState
                                                  .layerLinkAndKey(
                                                    event.eventId,
                                                  )
                                                  .key,
                                          // Pangea#
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              AppConfig.borderRadius,
                                            ),
                                          ),
                                          padding: noBubble || noPadding
                                              ? EdgeInsets.zero
                                              : const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 8,
                                                ),
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                // #Pangea
                                                // FluffyThemes.columnWidth * 1.5,
                                                event.messageType ==
                                                        MessageTypes.Image
                                                    ? double.infinity
                                                    : FluffyThemes.columnWidth *
                                                        1.5,
                                            // Pangea#
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              if (event.relationshipType ==
                                                  RelationshipTypes.reply)
                                                FutureBuilder<Event?>(
                                                  future: event.getReplyEvent(
                                                    timeline,
                                                  ),
                                                  builder: (
                                                    BuildContext context,
                                                    snapshot,
                                                  ) {
                                                    final replyEvent = snapshot
                                                            .hasData
                                                        ? snapshot.data!
                                                        : Event(
                                                            eventId: event
                                                                .relationshipEventId!,
                                                            content: {
                                                              'msgtype':
                                                                  'm.text',
                                                              'body': '...',
                                                            },
                                                            senderId:
                                                                event.senderId,
                                                            type:
                                                                'm.room.message',
                                                            room: event.room,
                                                            status: EventStatus
                                                                .sent,
                                                            originServerTs:
                                                                DateTime.now(),
                                                          );
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                        bottom: 4.0,
                                                      ),
                                                      child: InkWell(
                                                        borderRadius:
                                                            ReplyContent
                                                                .borderRadius,
                                                        onTap: () =>
                                                            scrollToEventId(
                                                          replyEvent.eventId,
                                                        ),
                                                        child: AbsorbPointer(
                                                          child: ReplyContent(
                                                            replyEvent,
                                                            ownMessage:
                                                                ownMessage,
                                                            timeline: timeline,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              MessageContent(
                                                displayEvent,
                                                textColor: textColor,
                                                onInfoTab: onInfoTab,
                                                borderRadius: borderRadius,
                                                // #Pangea
                                                pangeaMessageEvent:
                                                    pangeaMessageEvent,
                                                immersionMode: immersionMode,
                                                overlayController:
                                                    overlayController,
                                                controller: controller,
                                                nextEvent: nextEvent,
                                                prevEvent: previousEvent,
                                                // Pangea#
                                              ),
                                              if (event.hasAggregatedEvents(
                                                        timeline,
                                                        RelationshipTypes.edit,
                                                      )
                                                      // #Pangea
                                                      ||
                                                      (pangeaMessageEvent
                                                              ?.showUseType ??
                                                          false)
                                                  // Pangea#
                                                  )
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 4.0,
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      // #Pangea
                                                      if (event
                                                          .hasAggregatedEvents(
                                                        timeline,
                                                        RelationshipTypes.edit,
                                                      )) ...[
                                                        // Pangea#
                                                        Icon(
                                                          Icons.edit_outlined,
                                                          color: textColor
                                                              .withAlpha(164),
                                                          size: 14,
                                                        ),
                                                        Text(
                                                          ' - ${displayEvent.originServerTs.localizedTimeShort(context)}',
                                                          style: TextStyle(
                                                            color: textColor
                                                                .withAlpha(
                                                              164,
                                                            ),
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // #Pangea
                              if (overlayController == null)
                                MessageSentBy(event: event),
                              // Pangea#
                            ],
                          ),
                        ),
                        // #Pangea
                        if (controller.isStoryGameMode &&
                            alignment == Alignment.topRight &&
                            overlayController == null)
                          controller.storyGameAvatar(
                            event,
                            nextEvent,
                          )
                        else if (controller.isStoryGameMode &&
                            alignment == Alignment.topRight &&
                            overlayController != null)
                          const SizedBox(
                            height: Avatar.defaultSize,
                            width: Avatar.defaultSize,
                          ),
                        // Pangea#
                      ],
                    ),
                  ],
                ),
        );
      },
    );
    Widget container;
    final showReceiptsRow =
        event.hasAggregatedEvents(timeline, RelationshipTypes.reaction);
    // #Pangea
    // if (showReceiptsRow || displayTime || selected || displayReadMarker) {
    if (overlayController == null &&
        (showReceiptsRow ||
            displayTime ||
            displayReadMarker ||
            (pangeaMessageEvent?.showMessageButtons ?? false))) {
      // Pangea#
      container = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            ownMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          if (displayTime || selected)
            Padding(
              padding: displayTime
                  ? const EdgeInsets.symmetric(vertical: 8.0)
                  : EdgeInsets.zero,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    event.originServerTs.localizedTime(context),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12 * AppConfig.fontSizeFactor,
                      color: theme.colorScheme.secondary,
                      shadows: [
                        Shadow(
                          color: theme.colorScheme.surface,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          row,
          AnimatedSize(
            duration: FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            // #Pangea
            child: overlayController != null ||
                    (!showReceiptsRow &&
                        !(pangeaMessageEvent?.showMessageButtons ?? false))
                // child: !showReceiptsRow
                // Pangea#
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.only(
                      top: 4.0,
                      left: (ownMessage ? 0 : Avatar.defaultSize) + 12.0,
                      // #Pangea
                      // right: ownMessage ? 0 : 12.0,
                      right: (ownMessage ? 0 : Avatar.defaultSize) + 12.0,
                      // Pangea#
                    ),
                    // #Pangea
                    child: Row(
                      mainAxisAlignment:
                          // #Pangea
                          controller.isStoryGameMode
                              ? controller.storyGameMainAxisAlignment(event)
                              :
                              // Pangea#
                              ownMessage
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                      children: [
                        if (pangeaMessageEvent?.showMessageButtons ?? false)
                          MessageButtons(
                            controller: controller,
                            pangeaMessageEvent: pangeaMessageEvent!,
                            nextEvent: nextEvent,
                            prevEvent: previousEvent,
                          ),
                        MessageReactions(event, timeline),
                      ],
                    ),
                    // child: MessageReactions(event, timeline),
                    // Pangea#
                  ),
          ),
          if (displayReadMarker)
            Row(
              children: [
                Expanded(
                  child: Divider(color: theme.colorScheme.primary),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.primary,
                    ),
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  margin: const EdgeInsets.all(8.0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                  ),
                  child: Text(
                    L10n.of(context)!.readUpToHere,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
                Expanded(
                  child: Divider(color: theme.colorScheme.primary),
                ),
              ],
            ),
        ],
      );
    } else {
      container = row;
    }

    // #Pangea
    container = Material(type: MaterialType.transparency, child: container);
    // Pangea#

    return Center(
      child: Swipeable(
        key: ValueKey(event.eventId),
        background: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.0),
          child: Center(
            child: Icon(Icons.check_outlined),
          ),
        ),
        direction: AppConfig.swipeRightToLeftToReply
            ? SwipeDirection.endToStart
            : SwipeDirection.startToEnd,
        onSwipe: (_) => onSwipe(),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.columnWidth * 2.5,
          ),
          padding: EdgeInsets.only(
            left: 8.0,
            right: 8.0,
            top: nextEventSameSender ? 1.0 : 4.0,
            bottom:
                // #Pangea
                overlayController != null
                    ? 0
                    :
                    // Pangea#
                    previousEventSameSender
                        ? 1.0
                        : 4.0,
          ),
          child: container,
        ),
      ),
    );
  }
}
