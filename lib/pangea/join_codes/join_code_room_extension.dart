import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/chat_settings/constants/room_settings_constants.dart';
import 'package:fluffychat/pangea/join_codes/request_room_code_extension.dart';

extension JoinCodeRoomExtension on Room {
  String? get joinCode {
    final roomJoinRules = getState(EventTypes.RoomJoinRules, "");
    final accessCode = roomJoinRules?.content.tryGet(
      RoomSettingsConstants.accessCode,
    );
    return accessCode is String ? accessCode : null;
  }

  Future<void> addJoinCode() async {
    if (!canChangeStateEvent(EventTypes.RoomJoinRules)) {
      throw Exception('Cannot change join rules for this room');
    }

    final currentJoinRules = getState(EventTypes.RoomJoinRules)?.content ?? {};
    if (currentJoinRules[RoomSettingsConstants.accessCode] != null) return;

    final joinCode = await client.requestSpaceCode();
    currentJoinRules[RoomSettingsConstants.accessCode] = joinCode;

    await client.setRoomStateWithKey(
      id,
      EventTypes.RoomJoinRules,
      '',
      currentJoinRules,
    );
  }
}
