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

  const LeftPanelLayer({
    super.key,
    required this.token,
    required this.state,
    required this.foldedOver,
    required this.getRoomKey,
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
        token.type == PanelTypesEnum.addcourse &&
            state.extra is Completer<String>
        ? state.extra as Completer<String>
        : null;

    final panel = WorkspaceLeftPanel(
      token: token,
      currentUri: state.uri,
      foldedOver: foldedOver,
      shareItems: shareItems,
      courseCreationCompleter: courseCreationCompleter,
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
