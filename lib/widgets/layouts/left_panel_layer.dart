import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/routes/world/left_panel/workspace_left_panel.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';

/// Builds one left-column panel for [token]. A `room` panel is wrapped in a
/// roomId-keyed [GlobalKey] so the same [ChatController] is reparented (not
/// remounted) when its slot moves; other left surfaces are cheap to rebuild
/// and key by position.
class LeftPanelLayer extends StatelessWidget {
  final PanelToken token;
  final GoRouterState state;
  final bool foldedOver;
  final Function(String) getRoomKey;

  /// Render without the floating [PanelCard] chrome. The narrow full-screen
  /// focus (a live room / session) passes true: it covers the whole viewport,
  /// so the card's margins, rounding, and elevation only wasted edge space and
  /// let the map peek through (#7554). Purely a render fact — routing,
  /// tokens, and the allocator are untouched.
  final bool bare;

  const LeftPanelLayer({
    super.key,
    required this.token,
    required this.state,
    required this.foldedOver,
    required this.getRoomKey,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    // Forward any shared items (carried on the navigation `extra`, not the URL)
    // to a `room` token — the share sheet opens its target as the sole live
    // room, so the extra belongs to whichever room renders. See
    // `routing.instructions.md`.
    final shareItems =
        token.type == PanelTypesEnum.room && state.extra is List<ShareItem>
        ? state.extra as List<ShareItem>
        : null;

    final courseCreationCompleter =
        token.type == PanelTypesEnum.addcoursepage &&
            state.extra is Completer<String>
        ? state.extra as Completer<String>
        : null;

    final panel = FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: WorkspaceLeftPanel(
        token: token,
        currentUri: state.uri,
        foldedOver: foldedOver,
        shareItems: shareItems,
        courseCreationCompleter: courseCreationCompleter,
        bare: bare,
      ),
    );

    final type = token.type;
    final param = token.param;

    if (type == PanelTypesEnum.room && param is RoomTokenParam) {
      // The room token's param is `<roomid>` or `<roomid>/<subpage>`; the
      // GlobalKey is keyed by the bare room id only, so pushing a sub-page
      // (search/details/…) repositions the same ChatController rather than
      // remounting it. See `routing.instructions.md`.
      return KeyedSubtree(key: getRoomKey(fullRoomId(param.id)), child: panel);
    }
    return panel;
  }
}
