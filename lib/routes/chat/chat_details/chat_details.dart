import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details_content.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The shared room-details entry: resolves the room, shows the gone/left
/// error state, and rebuilds on this room's state updates. Everything
/// rendered is split by room type — a space renders [SpaceDetails] (the
/// course page), any other room renders [ChatDetailsContent].
class ChatDetails extends StatelessWidget {
  final String roomId;
  final Widget? embeddedCloseButton;

  /// The course-page section from the course token (spaces only).
  final SpaceSettingsTabs? activeTab;

  /// Whether [activeTab]'s full subpage ("See all") is pushed over the
  /// course card, from the course token's `<section>/all` param.
  final bool expandedSection;

  const ChatDetails({
    super.key,
    required this.roomId,
    this.embeddedCloseButton,
    this.activeTab,
    this.expandedSection = false,
  });

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null || room.membership == Membership.leave) {
      return Semantics(
        container: true,
        child: Scaffold(
          appBar: AppBar(
            // Give the error state the panel's close control (#8322) so a
            // stale or hand-edited course ID can't strand the user.
            leading: embeddedCloseButton,
            title: Text(L10n.of(context).oopsSomethingWentWrong),
          ),
          body: Center(
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return StreamBuilder(
      stream: room.client.onRoomState.stream.where(
        (update) => update.roomId == room.id,
      ),
      builder: (context, snapshot) => room.isSpace
          ? SpaceDetails(
              room: room,
              embeddedCloseButton: embeddedCloseButton,
              activeTab: activeTab,
              expandedSection: expandedSection,
            )
          : ChatDetailsContent(
              room: room,
              embeddedCloseButton: embeddedCloseButton,
            ),
    );
  }
}
