import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/generated/model.dart';

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

class LeftPanelRoomSubpage extends StatelessWidget {
  final RoomTokenParam? param;
  final List<ShareItem>? shareItems;
  final Widget closeButton;

  const LeftPanelRoomSubpage({
    super.key,
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
    if (room == null || room.isSpace || room.membership == Membership.leave) {
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
          .layerLinkAndKey("chat_page_with_room_$roomId")
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
