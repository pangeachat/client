import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_preview_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

extension ActivitySessionPreviewClientExtension on Client {
  Future<void> leavePreviewedActivitySessions() async {
    final previewedRoomIds =
        await ActivitySessionPreviewRepo.getPreviewedRoomIds();

    final toLeave = <Room>[];
    for (final roomId in previewedRoomIds) {
      final room = getRoomById(roomId);
      if (room?.membership != Membership.join) continue;
      if (room!.hasPickedRole) continue;
      toLeave.add(room);
    }

    final random = Random();
    for (final room in toLeave) {
      try {
        await room.leave();
      } catch (e, s) {
        ErrorHandler.logError(e: e, s: s, data: {'roomId': room.id});
      } finally {
        await ActivitySessionPreviewRepo.remove(room.id);
        await Future.delayed(Duration(seconds: random.nextInt(10)));
      }
    }
  }
}
