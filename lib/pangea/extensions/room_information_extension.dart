part of "pangea_room_extension.dart";

extension RoomInformationRoomExtension on Room {
  String? get creatorId => getState(EventTypes.RoomCreate)?.senderId;

  DateTime? get creationTimestamp {
    final creationEvent = getState(EventTypes.RoomCreate) as Event?;
    return creationEvent?.originServerTs;
  }

  Future<bool> get botIsInRoom async {
    final List<User> participants = await requestParticipants();
    return participants.any(
      (User user) => user.id == BotName.byEnvironment,
    );
  }

  String? get roomType =>
      getState(EventTypes.RoomCreate)?.content.tryGet<String>('type');

  bool isAnalyticsRoomOfUser(String userId) =>
      isAnalyticsRoom && isMadeByUser(userId);

  bool get isAnalyticsRoom => roomType == PangeaRoomTypes.analytics;

  bool get isHiddenRoom => isAnalyticsRoom || hasArchivedActivity;
}
