import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/chat/constants/default_power_level.dart';
import 'package:fluffychat/pangea/chat/extensions/create_room_extension.dart';
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
  }) async => createPangeaRoom(
    createRoom(
      creationContent: {'type': RoomCreationTypes.mSpace},
      visibility: visibility,
      name: name.trim(),
      topic: topic?.trim(),
      initialState: [
        await pangeaJoinRules(
          joinRules.toString().replaceAll('JoinRules.', ''),
        ),
        if (avatarUrl != null)
          StateEvent(type: EventTypes.RoomAvatar, content: {'url': avatarUrl}),
        if (initialState != null) ...initialState,
      ],
      powerLevelContentOverride: RoomDefaults.defaultSpacePowerLevelsContent(
        spaceChild: spaceChild,
      ),
    ),
  );
}
