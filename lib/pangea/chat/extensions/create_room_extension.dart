import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

extension CreateRoomExtension on Client {
  Future<String> createPangeaRoom(Future<String> roomFuture) async {
    String roomId;
    try {
      roomId = await roomFuture;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      rethrow;
    }

    try {
      final room = getRoomById(roomId);
      if (room == null || room.membership != Membership.join) {
        await waitForRoomInSync(
          roomId,
          join: true,
        ).timeout(Duration(seconds: 10));
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomId},
        level: e is TimeoutException ? SentryLevel.warning : SentryLevel.error,
      );

      if (e is! TimeoutException) {
        rethrow;
      }
    }

    return roomId;
  }

  Future<String> createPangeaDirectChat(
    String mxid, {
    List<StateEvent>? initialState,
  }) => createPangeaRoom(
    startDirectChat(
      mxid,
      initialState: initialState,
      enableEncryption: false,
      waitForSync: false,
    ),
  );

  Future<String> createPangeaGroupChat(
    String name, {
    List<StateEvent>? initialState,
  }) => createPangeaRoom(
    createGroupChat(
      visibility: Visibility.private,
      groupName: name,
      initialState: initialState,
      enableEncryption: false,
      waitForSync: false,
    ),
  );
}
