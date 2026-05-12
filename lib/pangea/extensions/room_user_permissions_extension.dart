part of "pangea_room_extension.dart";

extension UserPermissionsRoomExtension on Room {
  bool isMadeByUser(String userId) =>
      getState(EventTypes.RoomCreate)?.senderId == userId;

  bool get isRoomAdmin => ownPowerLevel >= SpaceConstants.powerLevelOfAdmin;

  List<User> get nonBotRoomAdminsLocal {
    final List<User> participants = getParticipants();
    return participants
        .where((e) => e.powerLevel >= 100 && e.id != BotName.byEnvironment)
        .toList();
  }

  Future<List<User>> get nonBotRoomAdmins async {
    final List<User> participants = await requestParticipants();
    return participants
        .where((e) => e.powerLevel >= 100 && e.id != BotName.byEnvironment)
        .toList();
  }
}
