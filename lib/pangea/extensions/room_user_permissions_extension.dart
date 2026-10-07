part of "pangea_room_extension.dart";

extension UserPermissionsRoomExtension on Room {
  bool isMadeByUser(String userId) =>
      getState(EventTypes.RoomCreate)?.senderId == userId;

  /// False for a signed-out account: the SDK's [ownPowerLevel] reads
  /// `client.userID!`, and the chat list can still build through logout
  /// (#9019).
  bool get isRoomAdmin =>
      client.userID != null &&
      ownPowerLevel >= SpaceConstants.powerLevelOfAdmin;

  /// Whether the user may redact an event sent by [senderId].
  ///
  /// Direct chats are created with the `trusted_private_chat` preset, so both
  /// members sit at admin power and [canRedact] alone would let each delete the
  /// other's messages. Direct chats follow every other room instead — your own
  /// messages only — while moderators keep the power level rule elsewhere
  /// (#8402).
  bool canRedactEventFrom(String senderId) =>
      senderId == client.userID || (!isDirectChat && canRedact);

  /// Whether the room's power levels let the user react. A read-only room such
  /// as announcements rejects a learner's reaction (#9167).
  bool get canSendReactions => canSendEvent(EventTypes.Reaction);

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
