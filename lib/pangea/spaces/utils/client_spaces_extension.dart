import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/chat/constants/default_power_level.dart';
import 'package:fluffychat/pangea/extensions/join_rule_extension.dart';

extension SpacesClientExtension on Client {
  Future<String> createPangeaSpace({
    required String name,
    String? topic,
    Visibility visibility = Visibility.private,
    JoinRules joinRules = JoinRules.public,
    String? avatarUrl,
    List<StateEvent>? initialState,
    int spaceChild = 50,
  }) async {
    final roomId = await createRoom(
      creationContent: {'type': RoomCreationTypes.mSpace},
      visibility: visibility,
      name: name.trim(),
      topic: topic?.trim(),
      powerLevelContentOverride: {'events_default': 100},
      initialState: [
        RoomDefaults.defaultSpacePowerLevels(
          userID!,
          spaceChild: spaceChild,
        ),
        await pangeaJoinRules(
          joinRules.toString().replaceAll('JoinRules.', ''),
        ),
        if (avatarUrl != null)
          StateEvent(
            type: EventTypes.RoomAvatar,
            content: {'url': avatarUrl},
          ),
        if (initialState != null) ...initialState,
      ],
    );

    if (getRoomById(roomId) == null) {
      await waitForRoomInSync(roomId, join: true);
    }

    return roomId;
  }
}
