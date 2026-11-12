/// The server refused the learner a discussion: they were removed or banned
/// from the course's room for it (403 `PANGEA_DISCUSSION_REMOVED`).
class DiscussionRemovedException implements Exception {
  /// The Matrix errcode synapse answers with.
  static const String errcode = 'PANGEA_DISCUSSION_REMOVED';

  const DiscussionRemovedException();

  @override
  String toString() => 'DiscussionRemovedException';
}

/// Join placed the learner in [roomId], but the room had not reached this
/// client when Join stopped waiting for it: sync lag, not a failed join.
class DiscussionRoomNotArrivedException implements Exception {
  final String roomId;

  const DiscussionRoomNotArrivedException(this.roomId);

  @override
  String toString() => 'DiscussionRoomNotArrivedException';
}
