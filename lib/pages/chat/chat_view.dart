import 'package:badges/badges.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_list_tile.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat/chat_emoji_picker.dart';
import 'package:fluffychat/pages/chat/chat_event_list.dart';
import 'package:fluffychat/pages/chat/pinned_events.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/pangea/choreographer/widgets/it_bar.dart';
import 'package:fluffychat/pangea/choreographer/widgets/start_igc_button.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/pages/games/story_game/game_chat.dart';
import 'package:fluffychat/pangea/widgets/animations/gain_points.dart';
import 'package:fluffychat/pangea/widgets/chat/chat_floating_action_button.dart';
import 'package:fluffychat/pangea/widgets/chat/input_bar_wrapper.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/connection_status_header.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import '../../utils/stream_extension.dart';

enum _EventContextAction { info, report }

class ChatView extends StatelessWidget {
  final ChatController controller;

  const ChatView(this.controller, {super.key});

  List<Widget> _appBarActions(BuildContext context) {
    // #Pangea
    final leaderboardBtn = CompositedTransformTarget(
      link: MatrixState.pAnyState.layerLinkAndKey('leaderboard_btn').link,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: IconButton(
          icon: const Icon(Icons.leaderboard_outlined),
          onPressed: controller.showLeaderboard,
          key: MatrixState.pAnyState.layerLinkAndKey('leaderboard_btn').key,
        ),
      ),
    );
    // Pangea#
    if (controller.selectMode) {
      return [
        if (controller.canEditSelectedEvents)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: L10n.of(context)!.edit,
            onPressed: controller.editSelectedEventAction,
          ),
        IconButton(
          icon: const Icon(Icons.copy_outlined),
          tooltip: L10n.of(context)!.copy,
          onPressed: controller.copyEventsAction,
        ),
        if (controller.canSaveSelectedEvent)
          // Use builder context to correctly position the share dialog on iPad
          Builder(
            builder: (context) => IconButton(
              icon: Icon(Icons.adaptive.share),
              tooltip: L10n.of(context)!.share,
              onPressed: () => controller.saveSelectedEvent(context),
            ),
          ),
        if (controller.canPinSelectedEvents)
          IconButton(
            icon: const Icon(Icons.push_pin_outlined),
            onPressed: controller.pinEvent,
            tooltip: L10n.of(context)!.pinMessage,
          ),
        if (controller.canRedactSelectedEvents)
          IconButton(
            icon: const Icon(Icons.delete_outlined),
            tooltip: L10n.of(context)!.redactMessage,
            onPressed: controller.redactEventsAction,
          ),
        if (controller.selectedEvents.length == 1
            // #Pangea
            // &&
            // !controller.isStoryGameMode
            // Pangea#
            )
          PopupMenuButton<_EventContextAction>(
            onSelected: (action) {
              switch (action) {
                case _EventContextAction.info:
                  controller.showEventInfo();
                  controller.clearSelectedEvents();
                  break;
                case _EventContextAction.report:
                  controller.reportEventAction();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _EventContextAction.info,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context)!.messageInfo),
                  ],
                ),
              ),
              if (controller.selectedEvents.single.status.isSent)
                PopupMenuItem(
                  value: _EventContextAction.report,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 12),
                      Text(L10n.of(context)!.reportMessage),
                    ],
                  ),
                ),
            ],
          ),
        // #Pangea
        leaderboardBtn,
        // Pangea#
      ];
      // #Pangea
    } else {
      return [
        leaderboardBtn,
        ChatSettingsPopupMenu(
          controller.room,
          (!controller.room.isDirectChat && !controller.room.isArchived),
        ),
      ];
    }
    // else if (!controller.room.isArchived) {
    //   return [
    //     if (Matrix.of(context).voipPlugin != null &&
    //         controller.room.isDirectChat)
    //       IconButton(
    //         onPressed: controller.onPhoneButtonTap,
    //         icon: const Icon(Icons.call_outlined),
    //         tooltip: L10n.of(context)!.placeCall,
    //       ),
    //     EncryptionButton(controller.room),
    //     ChatSettingsPopupMenu(controller.room, true),
    //   ];
    // }
    // return [];
    // Pangea#
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (controller.room.membership == Membership.invite) {
      showFutureLoadingDialog(
        context: context,
        future: () => controller.room.join(),
      );
      // #Pangea
      controller.room.leaveIfFull().then(
            (full) => full ? context.go('/rooms') : null,
          );
      // Pangea#
    }
    final bottomSheetPadding = FluffyThemes.isColumnMode(context) ? 16.0 : 8.0;
    final scrollUpBannerEventId = controller.scrollUpBannerEventId;

    final accountConfig = Matrix.of(context).client.applicationAccountConfig;

    return PopScope(
      canPop: controller.selectedEvents.isEmpty && !controller.showEmojiPicker,
      onPopInvokedWithResult: (pop, _) async {
        if (pop) return;
        if (controller.selectedEvents.isNotEmpty) {
          controller.clearSelectedEvents();
        } else if (controller.showEmojiPicker) {
          controller.emojiPickerAction();
        }
      },
      child: StreamBuilder(
        stream: controller.room.client.onRoomState.stream
            .where((update) => update.roomId == controller.room.id)
            .rateLimit(const Duration(seconds: 1)),
        builder: (context, snapshot) => FutureBuilder(
          future: controller.loadTimelineFuture,
          builder: (BuildContext context, snapshot) {
            var appbarBottomHeight = 0.0;
            if (controller.room.pinnedEventIds.isNotEmpty) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            if (scrollUpBannerEventId != null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            final tombstoneEvent =
                controller.room.getState(EventTypes.RoomTombstone);
            if (tombstoneEvent != null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            return Scaffold(
              appBar: AppBar(
                actionsIconTheme: IconThemeData(
                  color: controller.selectedEvents.isEmpty
                      ? null
                      : theme.colorScheme.primary,
                ),
                leading: controller.selectMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: controller.clearSelectedEvents,
                        tooltip: L10n.of(context)!.close,
                        color: theme.colorScheme.primary,
                      )
                    : StreamBuilder<Object>(
                        stream: Matrix.of(context)
                            .client
                            .onSync
                            .stream
                            .where((syncUpdate) => syncUpdate.hasRoomUpdate),
                        builder: (context, _) => UnreadRoomsBadge(
                          filter: (r) =>
                              r.id != controller.roomId
                              // #Pangea
                              &&
                              !r.isAnalyticsRoom,
                          // Pangea#
                          badgePosition: BadgePosition.topEnd(end: 8, top: 4),
                          child: const Center(child: BackButton()),
                        ),
                      ),
                titleSpacing: 0,
                title: ChatAppBarTitle(controller),
                actions: _appBarActions(context),
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(appbarBottomHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PinnedEvents(controller),
                      if (tombstoneEvent != null)
                        ChatAppBarListTile(
                          title: tombstoneEvent.parsedTombstoneContent.body,
                          leading: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.upgrade_outlined),
                          ),
                          trailing: TextButton(
                            onPressed: controller.goToNewRoomAction,
                            child: Text(L10n.of(context)!.goToTheNewRoom),
                          ),
                        ),
                      if (scrollUpBannerEventId != null)
                        ChatAppBarListTile(
                          leading: IconButton(
                            color: theme.colorScheme.onSurfaceVariant,
                            icon: const Icon(Icons.close),
                            tooltip: L10n.of(context)!.close,
                            onPressed: () {
                              controller.discardScrollUpBannerEventId();
                              controller.setReadMarker();
                            },
                          ),
                          title: L10n.of(context)!.jumpToLastReadMessage,
                          trailing: TextButton(
                            onPressed: () {
                              controller.scrollToEventId(
                                scrollUpBannerEventId,
                              );
                              controller.discardScrollUpBannerEventId();
                            },
                            child: Text(L10n.of(context)!.jump),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // #Pangea
              // floatingActionButton: controller.showScrollDownButton &&
              //         controller.selectedEvents.isEmpty
              //     ? Padding(
              //         padding: const EdgeInsets.only(bottom: 56.0),
              //         child: FloatingActionButton(
              //           onPressed: controller.scrollDown,
              //           heroTag: null,
              //           mini: true,
              //           child: const Icon(Icons.arrow_downward_outlined),
              //         ),
              //       )
              //     : null,
              // Pangea#
              body:
                  // #Pangea
                  // DropTarget(
                  //   onDragDone: controller.onDragDone,
                  //   onDragEntered: controller.onDragEntered,
                  //   onDragExited: controller.onDragExited,
                  //   child:
                  // Pangea#
                  Stack(
                children: <Widget>[
                  if (accountConfig.wallpaperUrl != null)
                    Opacity(
                      opacity: accountConfig.wallpaperOpacity ?? 1,
                      child: MxcImage(
                        uri: accountConfig.wallpaperUrl,
                        fit: BoxFit.cover,
                        isThumbnail: true,
                        width: FluffyThemes.columnWidth * 4,
                        height: FluffyThemes.columnWidth * 4,
                        placeholder: (_) => Container(),
                      ),
                    ),
                  SafeArea(
                    child:
                        // #Pangea
                        Stack(
                      children: [
                        // Pangea#
                        Column(
                          children: <Widget>[
                            Expanded(
                              child: GestureDetector(
                                onTap: controller.clearSingleSelectedEvent,
                                child: Builder(
                                  builder: (context) {
                                    if (controller.timeline == null) {
                                      return const Center(
                                        child:
                                            CircularProgressIndicator.adaptive(
                                          strokeWidth: 2,
                                        ),
                                      );
                                    }
                                    return ChatEventList(
                                      controller: controller,
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (controller.room.canSendDefaultMessages &&
                                controller.room.membership == Membership.join)
                              Container(
                                margin: EdgeInsets.only(
                                  bottom: bottomSheetPadding,
                                  left: bottomSheetPadding,
                                  right: bottomSheetPadding,
                                ),
                                constraints: const BoxConstraints(
                                  maxWidth: FluffyThemes.columnWidth * 2.5,
                                ),
                                alignment: Alignment.center,
                                child: Material(
                                  clipBehavior: Clip.hardEdge,
                                  color: theme
                                      .colorScheme
                                      // ignore: deprecated_member_use
                                      .surfaceVariant,
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(24),
                                  ),
                                  child: controller.room.isAbandonedDMRoom ==
                                          true
                                      ? Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            TextButton.icon(
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.all(
                                                  16,
                                                ),
                                                foregroundColor:
                                                    theme.colorScheme.error,
                                              ),
                                              icon: const Icon(
                                                Icons.archive_outlined,
                                              ),
                                              onPressed: controller.leaveChat,
                                              label: Text(
                                                L10n.of(context)!.leave,
                                              ),
                                            ),
                                            TextButton.icon(
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.all(
                                                  16,
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.forum_outlined,
                                              ),
                                              onPressed:
                                                  controller.recreateChat,
                                              label: Text(
                                                L10n.of(context)!.reopenChat,
                                              ),
                                            ),
                                          ],
                                        )
                                      :
                                      // #Pangea
                                      null,
                                  // Column(
                                  //     mainAxisSize: MainAxisSize.min,
                                  //     children: [
                                  //       const ConnectionStatusHeader(),
                                  //       // #Pangea
                                  //       ITBar(
                                  //         choreographer:
                                  //             controller.choreographer,
                                  //       ),
                                  //       // ReactionsPicker(controller),
                                  //       // Pangea#
                                  //       ReplyDisplay(controller),
                                  //       ChatInputRow(controller),
                                  // Pangea#
                                  //       ChatEmojiPicker(controller),
                                  //     ],
                                  //   ),
                                ),
                              ),
                            // #Pangea
                            // Keep messages above minimum input bar height
                            const SizedBox(
                              height: 60,
                            ),
                            // Pangea#
                          ],
                        ),
                        // #Pangea
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (!controller.selectMode)
                                Container(
                                  margin: EdgeInsets.only(
                                    bottom: 10,
                                    left: bottomSheetPadding,
                                    right: bottomSheetPadding,
                                  ),
                                  constraints: const BoxConstraints(
                                    maxWidth: FluffyThemes.columnWidth * 2.4,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      StartIGCButton(
                                        controller: controller,
                                      ),
                                      Row(
                                        children: [
                                          PointsGainedAnimation(
                                            gainColor: Theme.of(context)
                                                .colorScheme
                                                .onPrimary,
                                          ),
                                          const SizedBox(width: 100),
                                          ChatFloatingActionButton(
                                            controller: controller,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              Container(
                                margin: EdgeInsets.only(
                                  bottom: bottomSheetPadding,
                                  left: bottomSheetPadding,
                                  right: bottomSheetPadding,
                                ),
                                constraints: const BoxConstraints(
                                  maxWidth: FluffyThemes.columnWidth * 2.5,
                                ),
                                alignment: Alignment.center,
                                child: Material(
                                  clipBehavior: Clip.hardEdge,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(24),
                                  ),
                                  child: Column(
                                    children: [
                                      const ConnectionStatusHeader(),
                                      ITBar(
                                        choreographer: controller.choreographer,
                                      ),
                                      ReplyDisplay(controller),
                                      ChatInputRowWrapper(
                                        controller: controller,
                                      ),
                                      ChatEmojiPicker(controller),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Pangea#
                      ],
                    ),
                  ),
                  // #Pangea
                  // if (controller.dragging)
                  //   Container(
                  //     color: theme.scaffoldBackgroundColor.withOpacity(0.9),
                  //     alignment: Alignment.center,
                  //     child: const Icon(
                  //       Icons.upload_outlined,
                  //       size: 100,
                  //     ),
                  //   ),
                  // Pangea#
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
