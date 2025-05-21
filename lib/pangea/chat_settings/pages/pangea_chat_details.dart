import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pages/chat_details/participant_list_item.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/chat_settings/models/bot_options_model.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/class_name_header.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/conversation_bot/conversation_bot_settings.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/widgets/download_space_analytics_dialog.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PangeaChatDetailsView extends StatelessWidget {
  final ChatDetailsController controller;

  const PangeaChatDetailsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final room = Matrix.of(context).client.getRoomById(controller.roomId!);
    if (room == null || room.membership == Membership.leave) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).oopsSomethingWentWrong),
        ),
        body: Center(
          child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
        ),
      );
    }

    return StreamBuilder(
      stream: room.client.onRoomState.stream
          .where((update) => update.roomId == room.id),
      builder: (context, snapshot) {
        var members = room.getParticipants().toList()
          ..sort((b, a) => a.powerLevel.compareTo(b.powerLevel));
        members = members.take(10).toList();
        final actualMembersCount = (room.summary.mInvitedMemberCount ?? 0) +
            (room.summary.mJoinedMemberCount ?? 0);
        final canRequestMoreMembers = members.length < actualMembersCount;
        final displayname = room.getLocalizedDisplayname(
          MatrixLocals(L10n.of(context)),
        );
        return Scaffold(
          appBar: AppBar(
            leading: controller.widget.embeddedCloseButton ??
                (room.isSpace
                    ? const SizedBox()
                    : const Center(child: BackButton())),
            elevation: theme.appBarTheme.elevation,
            title: ClassNameHeader(
              controller: controller,
              room: room,
            ),
            centerTitle: true,
            backgroundColor: theme.appBarTheme.backgroundColor,
          ),
          body: MaxWidthBody(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: members.length + 1 + (canRequestMoreMembers ? 1 : 0),
              itemBuilder: (BuildContext context, int i) => i == 0
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Stack(
                                children: [
                                  Hero(
                                    tag:
                                        controller.widget.embeddedCloseButton !=
                                                null
                                            ? 'embedded_content_banner'
                                            : 'content_banner',
                                    child: Avatar(
                                      mxContent: room.avatar,
                                      name: displayname,
                                      // #Pangea
                                      userId: room.directChatMatrixID,
                                      // Pangea#
                                      size: Avatar.defaultSize * 2.5,
                                    ),
                                  ),
                                  if (!room.isDirectChat &&
                                      room.canChangeStateEvent(
                                        EventTypes.RoomAvatar,
                                      ))
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: FloatingActionButton.small(
                                        onPressed: controller.setAvatarAction,
                                        heroTag: null,
                                        child: const Icon(
                                          Icons.camera_alt_outlined,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => room.isDirectChat
                                        ? null
                                        : room.canChangeStateEvent(
                                            EventTypes.RoomName,
                                          )
                                            ? controller.setDisplaynameAction()
                                            : FluffyShare.share(
                                                displayname,
                                                context,
                                                copyOnly: true,
                                              ),
                                    icon: Icon(
                                      room.isDirectChat
                                          ? Icons.chat_bubble_outline
                                          : room.canChangeStateEvent(
                                              EventTypes.RoomName,
                                            )
                                              ? Icons.edit_outlined
                                              : Icons.copy_outlined,
                                      size: 16,
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.onSurface,
                                    ),
                                    label: Text(
                                      room.isDirectChat
                                          ? L10n.of(context).directChat
                                          : displayname,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => room.isDirectChat
                                        ? null
                                        : context.push(
                                            '/rooms/${controller.roomId}/details/members',
                                          ),
                                    icon: const Icon(
                                      Icons.group_outlined,
                                      size: 14,
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.secondary,
                                    ),
                                    label: Text(
                                      L10n.of(context).countParticipants(
                                        actualMembersCount,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Divider(color: theme.dividerColor, height: 1),
                        Stack(
                          children: [
                            if (room.isRoomAdmin)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: IconButton(
                                  onPressed: controller.setTopicAction,
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 24.0,
                                right: 24.0,
                                top: 16.0,
                                bottom: 16.0,
                              ),
                              child: SelectableLinkify(
                                text: room.topic.isEmpty
                                    ? room.isSpace
                                        ? L10n.of(context).noSpaceDescriptionYet
                                        : L10n.of(context).noChatDescriptionYet
                                    : room.topic,
                                options: const LinkifyOptions(humanize: false),
                                linkStyle: const TextStyle(
                                  color: Colors.blueAccent,
                                  decorationColor: Colors.blueAccent,
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontStyle: room.topic.isEmpty
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  color: theme.textTheme.bodyMedium!.color,
                                  decorationColor:
                                      theme.textTheme.bodyMedium!.color,
                                ),
                                onOpen: (url) =>
                                    UrlLauncher(context, url.url).launchUrl(),
                              ),
                            ),
                          ],
                        ),
                        RoomDetailsButtonRow(
                          controller: controller,
                          room: room,
                        ),
                      ],
                    )
                  : i < members.length + 1
                      ? ParticipantListItem(members[i - 1])
                      : ListTile(
                          title: Text(
                            L10n.of(context).loadCountMoreParticipants(
                              (actualMembersCount - members.length),
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: theme.scaffoldBackgroundColor,
                            child: const Icon(
                              Icons.group_outlined,
                              color: Colors.grey,
                            ),
                          ),
                          onTap: () => context.push(
                            '/rooms/${controller.roomId!}/details/members',
                          ),
                          trailing: const Icon(Icons.chevron_right_outlined),
                        ),
            ),
          ),
        );
      },
    );
  }
}

class RoomDetailsButtonRow extends StatefulWidget {
  final ChatDetailsController controller;
  final Room room;

  const RoomDetailsButtonRow({
    super.key,
    required this.controller,
    required this.room,
  });

  @override
  State<RoomDetailsButtonRow> createState() => RoomDetailsButtonRowState();
}

class RoomDetailsButtonRowState extends State<RoomDetailsButtonRow> {
  StreamSubscription? notificationChangeSub;

  @override
  void initState() {
    super.initState();
    notificationChangeSub ??= Matrix.of(context)
        .client
        .onSync
        .stream
        .where(
          (syncUpdate) =>
              syncUpdate.accountData?.any(
                (accountData) => accountData.type == 'm.push_rules',
              ) ??
              false,
        )
        .listen(
          (u) => setState(() {}),
        );
  }

  @override
  void dispose() {
    notificationChangeSub?.cancel();
    super.dispose();
  }

  final double _buttonWidth = 130.0;
  final double _buttonHeight = 80.0;

  final double _miniButtonWidth = 50.0;
  final double _buttonPadding = 4.0;

  double get _fullButtonWidth => _buttonWidth + (_buttonPadding * 2);
  double get _fullMiniButtonWidth => _miniButtonWidth + (_buttonPadding * 2);

  Room get room => widget.room;

  List<ButtonDetails> _buttons(BuildContext context) {
    final L10n l10n = L10n.of(context);
    return [
      ButtonDetails(
        title: l10n.activities,
        icon: const Icon(Icons.event_note_outlined),
        onPressed: () => room.isSpace
            ? context.go("/rooms/homepage/planner")
            : context.go("/rooms/${room.id}/details/planner"),
        visible: (room) => room.canSendDefaultStates,
      ),
      ButtonDetails(
        title: l10n.permissions,
        icon: const Icon(Icons.edit_attributes_outlined),
        onPressed: () => context.go('/rooms/${room.id}/details/permissions'),
        visible: (room) => room.isRoomAdmin && !room.isDirectChat,
      ),
      ButtonDetails(
        title: l10n.access,
        icon: const Icon(Icons.shield_outlined),
        onPressed: () => context.go('/rooms/${room.id}/details/access'),
        visible: (room) => room.isSpace && room.isRoomAdmin,
      ),
      ButtonDetails(
        title: room.pushRuleState == PushRuleState.notify
            ? l10n.notificationsOn
            : l10n.notificationsOff,
        icon: Icon(
          room.pushRuleState == PushRuleState.notify
              ? Icons.notifications_on_outlined
              : Icons.notifications_off_outlined,
        ),
        onPressed: () => showFutureLoadingDialog(
          context: context,
          future: () => room.setPushRuleState(
            room.pushRuleState == PushRuleState.notify
                ? PushRuleState.mentionsOnly
                : PushRuleState.notify,
          ),
        ),
        visible: (room) => !room.isSpace,
      ),
      ButtonDetails(
        title: l10n.invite,
        icon: const Icon(Icons.person_add_outlined),
        onPressed: () => context.go('/rooms/${room.id}/details/invite'),
        visible: (room) => room.canInvite && !room.isDirectChat,
      ),
      ButtonDetails(
        title: l10n.addSubspace,
        icon: const Icon(Icons.add_outlined),
        onPressed: widget.controller.addSubspace,
        visible: (room) =>
            room.isSpace &&
            room.canSendEvent(
              EventTypes.SpaceChild,
            ),
      ),
      ButtonDetails(
        title: l10n.downloadSpaceAnalytics,
        icon: const Icon(Icons.download_outlined),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => DownloadAnalyticsDialog(space: room),
          );
        },
        visible: (room) => room.isSpace && room.isRoomAdmin,
      ),
      ButtonDetails(
        title: l10n.download,
        icon: const Icon(Icons.download_outlined),
        onPressed: widget.controller.downloadChatAction,
        visible: (room) => room.ownPowerLevel >= 50 && !room.isSpace,
      ),
      ButtonDetails(
        title: l10n.botSettings,
        icon: const BotFace(
          width: 30.0,
          expression: BotExpression.idle,
        ),
        onPressed: () => showDialog<BotOptionsModel?>(
          context: context,
          builder: (BuildContext context) => ConversationBotSettingsDialog(
            room: room,
            onSubmit: widget.controller.setBotOptions,
          ),
        ),
        visible: (room) =>
            !room.isSpace && !room.isDirectChat && room.canInvite,
      ),
      ButtonDetails(
        title: l10n.chatCapacity,
        icon: const Icon(Icons.reduce_capacity),
        onPressed: widget.controller.setRoomCapacity,
        visible: (room) =>
            !room.isSpace && !room.isDirectChat && room.canSendDefaultStates,
      ),
      ButtonDetails(
        title: l10n.leave,
        icon: const Icon(Icons.logout_outlined),
        onPressed: () async {
          final confirmed = await showOkCancelAlertDialog(
            useRootNavigator: false,
            context: context,
            title: L10n.of(context).areYouSure,
            okLabel: L10n.of(context).leave,
            cancelLabel: L10n.of(context).no,
            message: room.isSpace
                ? L10n.of(context).leaveSpaceDescription
                : L10n.of(context).leaveRoomDescription,
            isDestructive: true,
          );
          if (confirmed != OkCancelResult.ok) return;
          final resp = await showFutureLoadingDialog(
            context: context,
            future: room.isSpace ? room.leaveSpace : room.leave,
          );
          if (!resp.isError) {
            context.go("/rooms?spaceId=clear");
          }
        },
        visible: (room) => room.membership == Membership.join,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final buttons = _buttons(context)
        .where(
          (button) => button.visible(room),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final fullButtonCapacity =
              (availableWidth / _fullButtonWidth).floor() - 1;
          final miniButtonCapacity =
              (availableWidth / _fullMiniButtonWidth).floor() - 1;

          final mini = fullButtonCapacity < 3;
          final capacity = mini ? miniButtonCapacity : fullButtonCapacity;

          final numVisibleButtons = min(buttons.length, capacity);

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(numVisibleButtons + 1, (index) {
              if (index == numVisibleButtons) {
                if (buttons.length == numVisibleButtons) {
                  return const SizedBox();
                } else if (buttons.length == numVisibleButtons + 1) {
                  return RoomDetailsButton(
                    mini: mini,
                    visible: true,
                    title: buttons[index].title,
                    icon: buttons[index].icon,
                    onPressed: buttons[index].onPressed,
                    width: mini ? _miniButtonWidth : _buttonWidth,
                    height: mini ? _miniButtonWidth : _buttonHeight,
                  );
                }
                return PopupMenuButton(
                  onSelected: (button) => button.onPressed(),
                  itemBuilder: (context) {
                    return buttons
                        .skip(numVisibleButtons)
                        .map(
                          (button) => PopupMenuItem(
                            value: button,
                            child: Row(
                              children: [
                                button.icon,
                                const SizedBox(width: 8),
                                Text(button.title),
                              ],
                            ),
                          ),
                        )
                        .toList();
                  },
                  child: RoomDetailsButton(
                    mini: mini,
                    visible: true,
                    title: L10n.of(context).more,
                    icon: const Icon(Icons.more_horiz_outlined),
                    width: mini ? _miniButtonWidth : _buttonWidth,
                    height: mini ? _miniButtonWidth : _buttonHeight,
                  ),
                );
              }

              final button = buttons[index];
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: _buttonPadding),
                child: RoomDetailsButton(
                  mini: mini,
                  visible: button.visible(room),
                  title: button.title,
                  icon: button.icon,
                  onPressed: button.onPressed,
                  width: mini ? _miniButtonWidth : _buttonWidth,
                  height: mini ? _miniButtonWidth : _buttonHeight,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class RoomDetailsButton extends StatelessWidget {
  final bool mini;
  final bool visible;

  final String title;
  final Widget icon;
  final VoidCallback? onPressed;

  final double width;
  final double height;

  const RoomDetailsButton({
    super.key,
    required this.visible,
    required this.title,
    required this.icon,
    required this.mini,
    required this.width,
    required this.height,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox();
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: HoverBuilder(
        builder: (context, hovered) {
          return GestureDetector(
            onTap: onPressed,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: hovered
                    ? Theme.of(context).colorScheme.primary.withAlpha(50)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8.0),
              child: mini
                  ? icon
                  : Column(
                      spacing: 8.0,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        icon,
                        Text(
                          title,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class ButtonDetails {
  final String title;
  final Widget icon;
  final VoidCallback onPressed;
  final bool Function(Room) visible;

  const ButtonDetails({
    required this.title,
    required this.icon,
    required this.onPressed,
    required this.visible,
  });
}
