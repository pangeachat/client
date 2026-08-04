import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_search/chat_search_page.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_details_subpage.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';

/// The pAnyState id of the nested [Navigator] that hosts a room panel's chat.
/// Keyed by the panel's TOKEN TYPE as well as the room id: the same room can
/// reopen under a different token — `room:X` from the chat list, then
/// `session:X` from the Stars archive once the activity ends — and a shared id
/// would GlobalKey-reparent the old Navigator into the new panel, preserving
/// the stale route whose close button drops the departed token (a no-op on the
/// live URL — the dead back button of #8142). Same-type moves still share one
/// id, so the ChatController repositions rather than remounts when its slot
/// moves.
String chatPanelNavigatorId(PanelTypesEnum tokenType, String roomId) =>
    "chat_page_with_room_${tokenType.name}_$roomId";

class LeftPanelRoomSubpage extends StatelessWidget {
  /// The panel's token type (`room`, `session`, or `archivedroom`) — part of
  /// the nested Navigator's identity, see [chatPanelNavigatorId].
  final PanelTypesEnum tokenType;
  final RoomTokenParam? param;
  final List<ShareItem>? shareItems;
  final Widget closeButton;

  const LeftPanelRoomSubpage({
    super.key,
    required this.tokenType,
    required this.param,
    required this.shareItems,
    required this.closeButton,
  });

  @override
  Widget build(BuildContext context) {
    // Give the empty state the panel's close control (#7746)
    // to avoid stranding the user
    final emptyPage = Scaffold(
      appBar: AppBar(leading: closeButton),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            L10n.of(context).youAreNoLongerParticipatingInThisChat,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );

    final id = param?.id;
    if (id == null) return emptyPage;

    final roomId = fullRoomId(id);
    final room = Matrix.of(context).client.getRoomById(roomId);
    final sub = param?.subpage ?? '';

    // A space has no timeline, so it must never render as a chat — drop to a
    // graceful empty state instead of spinning up a ChatController on it.
    if (room == null || room.isSpace) {
      return emptyPage;
    }

    // A `room:` token is a live chat. Once the user has left (or been removed
    // from) the room, getRoomById still returns the archived copy, which would
    // otherwise render as a chat — show the no-longer-participating state
    // instead (#8148). Archive panels (`session:`, `archivedroom:`) are meant
    // to display left rooms, so they fall through. Invites also fall through:
    // the chat view auto-joins them.
    if (tokenType == PanelTypesEnum.room &&
        {Membership.leave, Membership.ban}.contains(room.membership)) {
      return emptyPage;
    }

    // A jump-to-message (`e/<eventId>`) parses with no subPage, so it falls
    // through to the plain chat below with parsed.eventId set.
    if (sub.isNotEmpty) {
      switch (sub.split('/').first) {
        case 'search':
          return ChatSearchPage(
            roomId: roomId,
            embeddedCloseButton: closeButton,
          );
        case 'invite':
          return PangeaInvitationSelection(
            roomId: roomId,
            initialFilter: param?.filter,
            embeddedCloseButton: closeButton,
          );
        case 'details':
          final rest = sub.contains('/')
              ? sub.substring(sub.indexOf('/') + 1)
              : '';

          if (rest.isEmpty) {
            return ChatDetails(
              roomId: roomId,
              embeddedCloseButton: closeButton,
            );
          }

          final param = this.param;
          return LeftPanelRoomDetailsSubpage(
            roomId: roomId,
            param: param != null
                ? RoomSubpageTokenParam.fromRoomParam(param)
                : null,
            closeButton: closeButton,
          );
      }
    }

    // The chat: thread the jump-to-message `e/<eventId>` field (RoomToken) and
    // any shared items (ride the navigation `extra`) the retired route used to
    // read. A bare room and a jump-to-message both render here (no sub-page).
    return Navigator(
      key: MatrixState.pAnyState
          .layerLinkAndKey(chatPanelNavigatorId(tokenType, roomId))
          .key,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => ChatPage(
          roomId: roomId,
          eventId: param?.eventId,
          shareItems: shareItems,
          backButton: closeButton,
        ),
      ),
    );
  }
}
