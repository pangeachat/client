import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/pages/chat_details/room_details_analytics.dart';
import 'package:fluffychat/pangea/pages/chat_details/room_details_avatar_button.dart';
import 'package:fluffychat/pangea/pages/chat_details/room_details_dropdown.dart';
import 'package:fluffychat/pangea/pages/chat_details/room_details_header.dart';
import 'package:fluffychat/pangea/pages/chat_details/room_details_participants_list.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class PangeaChatDetailsView extends StatelessWidget {
  final ChatDetailsController controller;
  const PangeaChatDetailsView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    if (room == null || room.membership == Membership.leave) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context)!.oopsSomethingWentWrong),
        ),
        body: Center(
          child: Text(L10n.of(context)!.youAreNoLongerParticipatingInThisChat),
        ),
      );
    }

    // StreamBuilder is a widget that builds itself based on the latest
    // snapshot of interaction with a Stream. So, ChatDetails rebuilds
    // everytime there's something in the onRoomState stream for the active
    // room, i.e., changes to its title, topic, etc. This way the page
    // is kept up-to-date and setState() doesn't have to be called manually.
    return StreamBuilder(
      stream: room.client.onRoomState.stream
          .where((update) => update.roomId == room.id),
      builder: (context, snapshot) {
        return Scaffold(
          appBar: AppBar(
            leading: !room.isSpace
                ? controller.widget.embeddedCloseButton ??
                    const Center(child: BackButton())
                : BackButton(onPressed: () => context.go("/rooms")),
            elevation: Theme.of(context).appBarTheme.elevation,
            actions: <Widget>[
              if (controller.widget.embeddedCloseButton == null)
                ChatSettingsPopupMenu(room, false),
            ],
            title: RoomDetailsHeader(controller: controller),
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          ),
          body: MaxWidthBody(
            child: Column(
              children: [
                Row(
                  children: [
                    RoomDetailsAvatarButton(controller: controller),
                    Expanded(
                      child: Stack(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: controller.setTopicAction,
                              child: Container(
                                alignment: Alignment.topLeft,
                                constraints: const BoxConstraints(
                                  maxHeight: 100,
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    room.topic.isEmpty
                                        ? (room.isRoomAdmin
                                            ? (room.isSpace
                                                ? L10n.of(context)!
                                                    .classDescriptionDesc
                                                : L10n.of(context)!
                                                    .chatTopicDesc)
                                            : L10n.of(context)!.topicNotSet)
                                        : room.topic,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: controller.setTopicAction,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor,
                ),
                RoomDetailsAnalytics(room: room),
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor,
                ),
                RoomDetailsParticipantsList(room: room),
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor,
                ),
                RoomDetailsDropdown(controller: controller),
              ],
            ),
          ),
        );
      },
    );
  }
}
