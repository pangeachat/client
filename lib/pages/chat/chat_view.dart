import 'package:badges/badges.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat/chat_event_list.dart';
import 'package:fluffychat/pages/chat/pinned_events.dart';
import 'package:fluffychat/pages/chat/reactions_picker.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/pages/chat/tombstone_display.dart';
import 'package:fluffychat/pangea/choreographer/widgets/has_error_button.dart';
import 'package:fluffychat/pangea/choreographer/widgets/language_display_toggle.dart';
import 'package:fluffychat/pangea/choreographer/widgets/language_permissions_warning_buttons.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/pages/class_analytics/measure_able.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/connection_status_header.dart';
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
      // #Pangea
    } else {
      return [
        ChatSettingsPopupMenu(controller.room, !controller.room.isDirectChat),
      ];
    }
    // } else if (!controller.room.isArchived) {
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
      child: GestureDetector(
        onTapDown: (_) => controller.setReadMarker(),
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          onEnter: (_) => controller.setReadMarker(),
          child: StreamBuilder(
            stream: controller.room.onUpdate.stream
                .rateLimit(const Duration(seconds: 1)),
            builder: (context, snapshot) => FutureBuilder(
              future: controller.loadTimelineFuture,
              builder: (BuildContext context, snapshot) {
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
                                child:
                                    const Icon(Icons.arrow_downward_outlined),
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
                      SafeArea(
                        child: Column(
                          children: <Widget>[
                            TombstoneDisplay(controller),
                            if (scrollUpBannerEventId != null)
                              Material(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceVariant,
                                shape: Border(
                                  bottom: BorderSide(
                                    width: 1,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: ListTile(
                                  leading: IconButton(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    icon: const Icon(Icons.close),
                                    tooltip: L10n.of(context)!.close,
                                    onPressed: () {
                                      controller.discardScrollUpBannerEventId();
                                      controller.setReadMarker();
                                    },
                                  ),
                                  title: Text(
                                    L10n.of(context)!.jumpToLastReadMessage,
                                  ),
                                  contentPadding:
                                      const EdgeInsets.only(left: 8),
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
                              ),
                            PinnedEvents(controller),
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
                                        maxWidth:
                                            FluffyThemes.columnWidth * 2.5,
                                      ),
                                      alignment: Alignment.center,
                                      child: Material(
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(
                                            AppConfig.borderRadius,
                                          ),
                                          bottomRight: Radius.circular(
                                            AppConfig.borderRadius,
                                          ),
                                        ),
                                        elevation: 4,
                                        shadowColor: Colors.black.withAlpha(64),
                                        clipBehavior: Clip.hardEdge,
                                        color: Theme.of(context).brightness ==
                                                Brightness.light
                                            ? Colors.white
                                            : Colors.black,
                                        child: controller
                                                    .room.isAbandonedDMRoom ==
                                                true
                                            ? Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceEvenly,
                                                children: [
                                                  TextButton.icon(
                                                    style: TextButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16),
                                                      foregroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .error,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.archive_outlined,
                                                    ),
                                                    onPressed:
                                                        controller.leaveChat,
                                                    label: Text(
                                                      L10n.of(context)!.leave,
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    style: TextButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16),
                                                    ),
                                                    icon: const Icon(
                                                      Icons.forum_outlined,
                                                    ),
                                                    onPressed:
                                                        controller.recreateChat,
                                                    label: Text(
                                                      L10n.of(context)!
                                                          .reopenChat,
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
                            // Pangea#
                          ],
                        ),
                      ),
                    ],
                  ),
                  // ),
                );
              },
            ),
          ),
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