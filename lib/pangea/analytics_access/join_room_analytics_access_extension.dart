import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/pangea/analytics_access/course_settings_extension.dart';

class JoinResponse {
  final String roomId;
  final bool shouldShowAnalyticsAccessNotice;

  const JoinResponse({
    required this.roomId,
    required this.shouldShowAnalyticsAccessNotice,
  });
}

extension JoinRoomAnalyticsAccessClientExtension on Client {
  Future<JoinResponse> joinRoomWithAccessCheck(
    String roomIdOrAlias, {
    List<String>? serverName,
    List<String>? via,
    String? reason,
    ThirdPartySigned? thirdPartySigned,
  }) async {
    final resp = await joinRoom(
      roomIdOrAlias,
      serverName: serverName,
      via: via,
      reason: reason,
      thirdPartySigned: thirdPartySigned,
    );

    final showRequireAccess = await _checkIfRequireAccess(resp);
    return JoinResponse(
      roomId: resp,
      shouldShowAnalyticsAccessNotice: showRequireAccess,
    );
  }

  Future<JoinResponse> joinRoomByIdWithAccessCheck(
    String roomId, {
    String? reason,
    ThirdPartySigned? thirdPartySigned,
  }) async {
    final resp = await joinRoomById(
      roomId,
      reason: reason,
      thirdPartySigned: thirdPartySigned,
    );
    final showRequireAccess = await _checkIfRequireAccess(resp);
    return JoinResponse(
      roomId: resp,
      shouldShowAnalyticsAccessNotice: showRequireAccess,
    );
  }

  Future<bool> _checkIfRequireAccess(String roomId) async {
    Room? room = getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      await waitForRoomInSync(
        roomId,
        join: true,
      ).timeout(Duration(seconds: 10));
    }

    room = getRoomById(roomId);
    if (room == null) {
      throw "Room not found after joining";
    }

    return room.requireAnalyticsAccess && !sawAccessNotice(roomId);
  }
}

extension JoinRoomAnalyticsAccessRoomExtension on Room {
  Future<JoinResponse> joinWithAccessCheck() async {
    await join();
    final showRequireAccess = await client._checkIfRequireAccess(id);
    return JoinResponse(
      roomId: id,
      shouldShowAnalyticsAccessNotice: showRequireAccess,
    );
  }
}
