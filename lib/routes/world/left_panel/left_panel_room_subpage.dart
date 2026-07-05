import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/generated/model.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/room_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_search/chat_search_page.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_details_subpage.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';

class LeftPanelRoomSubpage extends StatelessWidget {
  final PanelToken token;
  final Uri currentUri;
  final bool foldedOver;
  final bool isColumnMode;
  final List<ShareItem>? shareItems;

  const LeftPanelRoomSubpage({
    super.key,
    required this.token,
    required this.currentUri,
    required this.foldedOver,
    required this.isColumnMode,
    required this.shareItems,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = RoomToken.parse(token.param ?? '');
    final sub = parsed.subPage ?? '';
    final roomId = fullRoomId(parsed.id);
    final room = Matrix.of(context).client.getRoomById(roomId);

    // A space has no timeline, so it must never render as a chat — drop to a
    // graceful empty state instead of spinning up a ChatController on it.
    if (room == null || room.isSpace || room.membership == Membership.leave) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            L10n.of(context).youAreNoLongerParticipatingInThisChat,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final back = LeftPanelCloseButton(
      token: token,
      currentUri: currentUri,
      foldedOver: foldedOver,
      isColumnMode: isColumnMode,
    );

    // A jump-to-message (`e/<eventId>`) parses with no subPage, so it falls
    // through to the plain chat below with parsed.eventId set.
    if (sub.isNotEmpty) {
      switch (sub.split('/').first) {
        case 'search':
          return ChatSearchPage(roomId: roomId, embeddedCloseButton: back);
        case 'invite':
          return PangeaInvitationSelection(
            roomId: roomId,
            initialFilter: InvitationFilter.fromNullableString(parsed.filter),
            embeddedCloseButton: back,
          );
        case 'details':
          final rest = sub.contains('/')
              ? sub.substring(sub.indexOf('/') + 1)
              : '';

          if (rest.isEmpty) {
            return ChatDetails(roomId: roomId, embeddedCloseButton: back);
          }

          return LeftPanelRoomDetailsSubpage(
            token: token,
            currentUri: currentUri,
            foldedOver: foldedOver,
            isColumnMode: isColumnMode,
            roomId: roomId,
            name: rest.split('/').first,
            filter: parsed.filter,
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
          eventId: parsed.eventId,
          shareItems: shareItems,
          backButton: back,
        ),
      ),
    );
  }
}
