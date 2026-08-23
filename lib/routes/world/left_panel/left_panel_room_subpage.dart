import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/pangea/common/widgets/room_unavailable_panel.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
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
    final emptyPage = RoomUnavailablePanel(closeButton: closeButton);

    final id = param?.id;
    if (id == null) return emptyPage;

    final roomId = fullRoomId(id);
    final room = Matrix.of(context).client.getRoomById(roomId);
    final sub = param?.subpage ?? '';

    // A space has no timeline, so it must never render as a chat — drop to a
    // graceful empty state instead of spinning up a ChatController on it.
    // A LEFT room deliberately does NOT drop here: getRoomById also returns
    // archived rooms, and those stay viewable as read-only chats (#8148).
    if (room == null || room.isSpace) {
      return emptyPage;
    }

    // An analytics room is an internal construct store, never a chat surface
    // (#8268). Every list hides it (isHiddenRoom), but a direct URL or a stale
    // history entry can still name it in a panel token — drop that token as a
    // history REPLACE (so back does not land here again), revealing the course
    // context or map beneath, instead of rendering its timeline.
    if (room.isAnalyticsRoom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final close = roomTokenCloseLocation(
          GoRouterState.of(context).uri,
          roomId,
        );
        if (close != null) context.replace(close);
      });
      return const SizedBox.shrink();
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
    // The nested Navigator keeps this panel's overlays and dialogs inside the
    // panel instead of over the whole app. Its MaterialPageRoute lays down a
    // ModalBarrier, and ModalBarrier renders BlockSemantics, which drops the
    // semantics of everything painted BEFORE it — the sibling panel to the
    // left. That drop stops propagating at a semantic boundary, and a
    // semantics container is one, so this confines the blocking to the panel.
    // Without it the whole chat list — rows and search field alike —
    // disappears from the accessibility tree whenever a chat is open, and
    // the search field, having no DOM input, cannot be typed into (#8459).
    // The empty state above carries the same wrapper.
    return Semantics(
      container: true,
      child: Navigator(
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
      ),
    );
  }
}
