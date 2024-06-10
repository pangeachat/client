import 'package:badges/badges.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_list_tile.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat/chat_event_list.dart';
import 'package:fluffychat/pages/chat/pinned_events.dart';
import 'package:fluffychat/pages/chat/reactions_picker.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/pangea/choreographer/widgets/has_error_button.dart';
import 'package:fluffychat/pangea/choreographer/widgets/language_permissions_warning_buttons.dart';
import 'package:fluffychat/pangea/choreographer/widgets/start_igc_button.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/pages/class_analytics/measure_able.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/connection_status_header.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';
import 'package:matrix/matrix.dart';

import '../../utils/stream_extension.dart';
import 'chat_emoji_picker.dart';
import 'chat_input_row.dart';

enum _EventContextAction { info, report }

class ChatView extends StatelessWidget {
  final ChatController controller;

  const ChatView(this.controller, {super.key});

  List<Widget> _appBarActions(BuildContext context) {
    if (controller.selectMode) {
      return [
        if (controller.canEditSelectedEvents)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: L10n.of(context)!.edit,
            onPressed: controller.editSelectedEventAction,
          ),
        // #Pangea
        if (controller.selectedEvents.length == 1 &&
            controller.selectedEvents.single.messageType == MessageTypes.Text)
          // Pangea#
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
        if (controller.selectedEvents.length == 1)
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
              // #Pangea
              // PopupMenuItem(
              //   value: _EventContextAction.info,
              //   child: Row(
              //     mainAxisSize: MainAxisSize.min,
              //     children: [
              //       const Icon(Icons.info_outlined),
              //       const SizedBox(width: 12),
              //       Text(L10n.of(context)!.messageInfo),
              //     ],
              //   ),
              // ),
              // Pangea#
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
      ];
    }
    // #Pangea
    else {
      return [
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
    if (controller.room.membership == Membership.invite) {
      showFutureLoadingDialog(
        context: context,
        future: () => controller.room.join(),
      );
    }
    final bottomSheetPadding = FluffyThemes.isColumnMode(context) ? 16.0 : 8.0;
    final scrollUpBannerEventId = controller.scrollUpBannerEventId;

    final accountConfig = Matrix.of(context).client.applicationAccountConfig;

    return PopScope(
      canPop: controller.selectedEvents.isEmpty && !controller.showEmojiPicker,
      onPopInvoked: (pop) async {
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
              appbarBottomHeight += 42;
            }
            if (scrollUpBannerEventId != null) {
              appbarBottomHeight += 42;
            }
            final tombstoneEvent =
                controller.room.getState(EventTypes.RoomTombstone);
            if (tombstoneEvent != null) {
              appbarBottomHeight += 42;
            }
            return Scaffold(
              appBar: AppBar(
                actionsIconTheme: IconThemeData(
                  color: controller.selectedEvents.isEmpty
                      ? null
                      : Theme.of(context).colorScheme.primary,
                ),
                leading: controller.selectMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: controller.clearSelectedEvents,
                        tooltip: L10n.of(context)!.close,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : UnreadRoomsBadge(
                        filter: (r) =>
                            r.id != controller.roomId
                            // #Pangea
                            &&
                            !r.isAnalyticsRoom,
                        // Pangea#
                        badgePosition: BadgePosition.topEnd(end: 8, top: 4),
                        child: const Center(child: BackButton()),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
              floatingActionButton: controller.selectedEvents.isEmpty
                  ? (controller.showScrollDownButton
                      // Pangea#
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 56.0),
                          child: FloatingActionButton(
                            onPressed: controller.scrollDown,
                            heroTag: null,
                            mini: true,
                            child: const Icon(Icons.arrow_downward_outlined),
                          ),
                        )
                      // #Pangea
                      : controller.choreographer.errorService.error != null
                          ? ChoreographerHasErrorButton(
                              controller.pangeaController,
                              controller.choreographer.errorService.error!,
                            )
                          : controller.showPermissionsError
                              ? LanguagePermissionsButtons(
                                  choreographer: controller.choreographer,
                                  roomID: controller.roomId,
                                )
                              : null)
                  // #Pangea
                  : null,
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
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: GestureDetector(
                            onTap: controller.clearSingleSelectedEvent,
                            child: Builder(
                              builder: (context) {
                                if (controller.timeline == null) {
                                  return const Center(
                                    child: CircularProgressIndicator.adaptive(
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
                          // #Pangea
                          // Container(
                          ConditionalFlexible(
                            isScroll: controller.isRowScrollable,
                            child: ConditionalScroll(
                              isScroll: controller.isRowScrollable,
                              child: MeasurableWidget(
                                onChange: (size, position) {
                                  controller.inputRowSize = size!.height;
                                },
                                child: Container(
                                  // Pangea#
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
                                              // #Pangea
                                              if (controller.room.isRoomAdmin)
                                                TextButton.icon(
                                                  style: TextButton.styleFrom(
                                                    padding:
                                                        const EdgeInsets.all(
                                                      16,
                                                    ),
                                                    foregroundColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.archive_outlined,
                                                  ),
                                                  onPressed:
                                                      controller.archiveChat,
                                                  label: Text(
                                                    L10n.of(context)!.archive,
                                                  ),
                                                ),
                                              // Pangea#
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets.all(
                                                    16,
                                                  ),
                                                  foregroundColor:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                ),
                                                icon: const Icon(
                                                  // #Pangea
                                                  // Icons.archive_outlined,
                                                  Icons.arrow_forward,
                                                  // Pangea#
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
                                        : Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const ConnectionStatusHeader(),
                                              ReactionsPicker(controller),
                                              ReplyDisplay(controller),
                                              ChatInputRow(controller),
                                              ChatEmojiPicker(controller),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // #Pangea
                  // if (controller.dragging)
                  //   Container(
                  //     color: Theme.of(context)
                  //         .scaffoldBackgroundColor
                  //         .withOpacity(0.9),
                  //     alignment: Alignment.center,
                  //     child: const Icon(
                  //       Icons.upload_outlined,
                  //       size: 100,
                  //     ),
                  //   ),
                  Positioned(
                    left: 20,
                    bottom: 75,
                    child: StartIGCButton(controller: controller),
                  ),
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

// #Pangea
Widget ConditionalFlexible({required bool isScroll, required Widget child}) {
  if (isScroll) {
    return Flexible(
      flex: 9999999,
      child: child,
    );
  }
  return child;
}

class ConditionalScroll extends StatelessWidget {
  final bool isScroll;
  final Widget child;
  const ConditionalScroll({
    super.key,
    required this.isScroll,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (isScroll) {
      return SingleChildScrollView(
        child: child,
      );
    }
    return child;
  }
}
// #Pangea
