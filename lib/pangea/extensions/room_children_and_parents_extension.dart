part of "pangea_room_extension.dart";

extension ChildrenAndParentsRoomExtension on Room {
  Room? get firstSpaceParent {
    for (final parent in spaceParents) {
      if (parent.roomId == null) continue;
      final room = client.getRoomById(parent.roomId!);
      if (room != null) return room;
    }
    return null;
  }

  List<Room> get pangeaSpaceParents => client.rooms
      .where((r) => r.isSpace)
      .where((space) => space.spaceChildren.any((room) => room.roomId == id))
      .toList();

  List<Room> get pangeaSpaceChildren {
    final childIds = spaceChildren.map((child) => child.roomId).toSet();
    return client.rooms.where((r) => childIds.contains(r.id)).toList();
  }

  /// The ids of this space's direct `m.space.child` rooms, joined or not. A
  /// child removed from the space carries no `via` and is already dropped by
  /// [spaceChildren]. Empty for a room that is not a space (a stale or crafted
  /// course id), where [spaceChildren] would throw.
  Set<String> get spaceChildIds => !isSpace
      ? const {}
      : spaceChildren.map((child) => child.roomId).whereType<String>().toSet();

  /// The newest event in this space or in any child chat or activity session
  /// the user has joined. A course space's own timeline is mostly setup state,
  /// so its real activity lives in its children (#9004). Analytics rooms are
  /// excluded: a learner's analytics room is a child of every course they are
  /// in, so its membership changes would move all of those courses at once.
  /// Meaningful for joined spaces only: an invite's
  /// [Room.latestEventReceivedTime] is the current time.
  DateTime get spaceActivityTime =>
      [
            this,
            ...pangeaSpaceChildren.where(
              (child) =>
                  child.membership == Membership.join && !child.isAnalyticsRoom,
            ),
          ]
          .map((room) => room.latestEventReceivedTime)
          .reduce((a, b) => a.isAfter(b) ? a : b);

  /// Wrapper around call to setSpaceChild with added functionality
  /// to prevent adding one room to multiple spaces, and resets the
  /// subspace's JoinRules and Visibility to defaults.
  Future<void> addToSpace(String roomId, {bool? suggested}) async {
    final Room? child = client.getRoomById(roomId);
    if (child == null) return;

    for (final Room parent in child.pangeaSpaceParents) {
      try {
        await parent.removeSpaceChild(roomId);
      } catch (e) {
        ErrorHandler.logError(
          e: e,
          data: {"roomID": roomId, "parentID": parent.id},
        );
      }
    }

    await _trySetSpaceChild(roomId, suggested: suggested);
  }

  /// Add [roomId] as a child of this space WITHOUT removing it from its
  /// other space parents. Used when one activity session is shared into
  /// several course spaces at once.
  Future<void> addSpaceChildKeepingParents(String roomId, {bool? suggested}) =>
      _trySetSpaceChild(roomId, suggested: suggested);

  Future<void> _trySetSpaceChild(
    String roomId, {
    bool? suggested,
    int retries = 0,
  }) async {
    final Room? child = client.getRoomById(roomId);
    if (child == null) return;

    try {
      await setSpaceChild(roomId, suggested: suggested);
    } catch (err) {
      retries++;
      if (retries < 3) {
        await Future.delayed(const Duration(seconds: 1));
        return _trySetSpaceChild(
          roomId,
          suggested: suggested,
          retries: retries,
        );
      } else {
        rethrow;
      }
    }
  }

  /// A map of child suggestion status for a space.
  Map<String, bool> get spaceChildSuggestionStatus {
    if (!isSpace) return {};
    final Map<String, bool> suggestionStatus = {};
    for (final child in spaceChildren) {
      suggestionStatus[child.roomId!] = child.suggested ?? true;
    }
    return suggestionStatus;
  }

  /// The number of child rooms to display for a given space.
  int get spaceChildCount => client.rooms
      .where(
        (r) => spaceChildren.any(
          (child) => r.id == child.roomId && !r.isHiddenRoom,
        ),
      )
      .length;
}
