import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension BotActivtyRoleRoomExtension on Room {
  bool get botAddedToActivity =>
      getState(PangeaEventTypes.botParticipant) != null;

  Future<void> addBotToActivity() =>
      client.setRoomStateWithKey(id, PangeaEventTypes.botParticipant, "", {});
}
