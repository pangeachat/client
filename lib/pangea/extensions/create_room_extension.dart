import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/named_timeout.dart';

extension CreateRoomExtension on Client {
  /// [waitForSync] false returns as soon as the server has created the room,
  /// before it reaches the local store; the caller then owns calling
  /// [waitForCreatedRoom] if it needs the local [Room].
  Future<String> createPangeaRoom(
    Future<String> roomFuture, {
    bool waitForSync = true,
  }) async {
    String roomId;
    try {
      roomId = await roomFuture;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      rethrow;
    }

    if (waitForSync) await waitForCreatedRoom(roomId);
    return roomId;
  }

  /// Waits, bounded, for a room this client just created to arrive in sync.
  /// A timeout is logged and swallowed; any other failure is logged and
  /// rethrown.
  Future<void> waitForCreatedRoom(String roomId) async {
    try {
      final room = getRoomById(roomId);
      if (room == null || room.membership != Membership.join) {
        await waitForRoomInSync(roomId, join: true).timeoutNamed(
          const Duration(seconds: 10),
          'waitForRoomInSync: create room',
        );
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
    Map<String, dynamic>? powerLevelContentOverride,
  }) => createPangeaRoom(
    createGroupChat(
      visibility: Visibility.private,
      groupName: name,
      initialState: initialState,
      enableEncryption: false,
      waitForSync: false,
      powerLevelContentOverride: powerLevelContentOverride,
    ),
  );
}
