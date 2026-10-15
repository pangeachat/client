part of "pangea_room_extension.dart";

extension RoomInformationRoomExtension on Room {
  String? get creatorId => getState(EventTypes.RoomCreate)?.senderId;

  DateTime? get creationTimestamp {
    final creationEvent = getState(EventTypes.RoomCreate) as Event?;
    return creationEvent?.originServerTs;
  }

  String? get roomType =>
      getState(EventTypes.RoomCreate)?.content.tryGet<String>('type');

  /// Kept out of every chat list: analytics rooms, review-only rooms, and
  /// activity sessions that are over — saved by the learner, or finished for
  /// everyone. A finished activity lives on the Learning Objectives page and
  /// the map, not in Chats.
  bool get isHiddenRoom =>
      isAnalyticsRoom ||
      hasArchivedActivity ||
      isAdminReviewOnly ||
      (isActivitySession && isActivityFinished);
}
