part of "pangea_room_extension.dart";

extension RoomInformationRoomExtension on Room {
  String? get creatorId => getState(EventTypes.RoomCreate)?.senderId;

  bool isFirstOrSecondChild(String roomId) {
    return isSpace &&
        (spaceChildren.any((room) => room.roomId == roomId) ||
            spaceChildren
                .where((sc) => sc.roomId != null)
                .map((sc) => client.getRoomById(sc.roomId!))
                .any(
                  (room) =>
                      room != null &&
                      room.isSpace &&
                      room.spaceChildren.any((room) => room.roomId == roomId),
                ));
  }

  bool get isBotChat {
    return getParticipants().any(
      (User user) => user.id == BotName.byEnvironment,
    );
  }

  bool isAnalyticsRoomOfUser(String userId) =>
      isAnalyticsRoom && isMadeByUser(userId);

  bool get isAnalyticsRoom =>
      getState(EventTypes.RoomCreate)?.content.tryGet<String>('type') ==
      PangeaRoomTypes.analytics;

  bool get isHiddenRoom => isAnalyticsRoom || isHiddenActivityRoom;
}
