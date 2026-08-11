import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum SpaceGoneReason { deleted, removed }

/// Detects that a space the user is viewing is gone — deleted by an admin
/// (the server marks each member's leave event, see synapse-pangea-chat's
/// delete-room.instructions.md) or the user was kicked/banned — and shows a
/// dialog that removes the space on confirmation (#8237).
class SpaceGoneGate {
  /// Content key the delete_room synapse module sets on leave events.
  static const deletedContentKey = 'pangea.room_deleted';

  static final Set<String> _handled = {};
  static final Set<String> _locallyDeleted = {};

  /// Call before deleting a space so the deleting admin's own marked
  /// self-leave doesn't pop the dialog mid-flow.
  static void suppressFor(String roomId) => _locallyDeleted.add(roomId);

  static SpaceGoneReason? classify({
    required Membership membership,
    required bool hasDeletedMarker,
    required bool senderIsSelf,
  }) {
    if (membership != Membership.leave && membership != Membership.ban) {
      return null;
    }
    if (hasDeletedMarker) return SpaceGoneReason.deleted;
    if (!senderIsSelf) return SpaceGoneReason.removed;
    return null;
  }

  static SpaceGoneReason? reasonFor(Room room) {
    if (_locallyDeleted.contains(room.id)) return null;
    final member = room.getState(EventTypes.RoomMember, room.client.userID!);
    if (member == null) return null;
    return classify(
      membership: room.membership,
      hasDeletedMarker: member.content[deletedContentKey] == true,
      senderIsSelf: member.senderId == room.client.userID,
    );
  }

  /// Shows the dialog once per space per session, then forgets the space and
  /// resets to the world map.
  static Future<void> maybeShowDialog(
    BuildContext context,
    String roomId,
  ) async {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null || !room.isSpace || _handled.contains(roomId)) return;
    final reason = reasonFor(room);
    if (reason == null) return;
    _handled.add(roomId);

    await showOkAlertDialog(
      context: context,
      title: L10n.of(context).courseNoLongerAvailableTitle,
      message: reason == SpaceGoneReason.deleted
          ? L10n.of(context).courseDeletedDialogDesc
          : L10n.of(context).removedFromCourseError,
    );

    try {
      await room.forget();
    } catch (_) {
      // Best effort — the server may already have purged the room.
    }
    if (context.mounted) context.go(WorkspaceNav.clearAll());
  }
}
