part of "pangea_room_extension.dart";

extension RoomInformationRoomExtension on Room {
  String? get creatorId => getState(EventTypes.RoomCreate)?.senderId;

  DateTime? get creationTimestamp {
    final creationEvent = getState(EventTypes.RoomCreate) as Event?;
    return creationEvent?.originServerTs;
  }

  String? get roomType =>
      getState(EventTypes.RoomCreate)?.content.tryGet<String>('type');

  bool get isHiddenRoom => isAnalyticsRoom || hasArchivedActivity;
}
