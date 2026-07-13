import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';

/// The location that closes an open room-panel token for [roomId]: it drops
/// ONLY that token, so the rest of the workspace — notably the chat list —
/// survives. Closing an activity plan (#7156) and leaving a chat (#7561) must
/// not also clear the chat list. Returns null when no such token is open (e.g.
/// the standalone `/<activityId>` route) — the caller pops or falls back.
String? roomTokenCloseLocation(Uri uri, String? roomId) {
  if (roomId == null || roomId.isEmpty) return null;

  bool matches(PanelToken t) {
    if (!t.type.isRoomPanel) return false;

    final param = t.param;
    if (param == null || param is! RoomTokenParam) return false;
    return shortRoomId(param.id) == shortRoomId(roomId);
  }

  final panels = parseOpenPanels(uri);

  for (final t in panels.left) {
    if (matches(t)) return WorkspaceNav.closeLeft(uri, t);
  }

  for (final t in panels.right) {
    if (matches(t)) return WorkspaceNav.closeRight(uri, t);
  }

  return null;
}
