part of "pangea_room_extension.dart";

extension UserPermissionsRoomExtension on Room {
  bool isMadeByUser(String userId) =>
      getState(EventTypes.RoomCreate)?.senderId == userId;

  bool get isRoomAdmin => ownPowerLevel >= SpaceConstants.powerLevelOfAdmin;

  /// The users currently knocking on this room, from the locally loaded member
  /// list. Empty for non-admins: only an admin can accept/deny a knock, so
  /// knock indicators are admin-only by design (#8139). Callers that need the
  /// full member list loaded should sit under a `KnockingUsersBuilder`.
  List<User> get knockingUsers =>
      isRoomAdmin ? getParticipants([Membership.knock]) : [];

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
