part of "client_extension.dart";

extension GeneralInfoClientExtension on Client {
  Future<List<String>> get _teacherRoomIds async {
    final List<String> adminRoomIds = [];
    for (final Room adminSpace in (await _spacesImTeaching)) {
      adminRoomIds.add(adminSpace.id);
      final List<String> adminSpaceRooms = adminSpace.allSpaceChildRoomIds;
      adminRoomIds.addAll(adminSpaceRooms);
    }
    return adminRoomIds;
  }

  Future<List<User>> get _myTeachers async {
    final List<User> teachers = [];
    for (final classRoom in spacesImIn) {
      for (final teacher in await classRoom.teachers) {
        // If person requesting list of teachers is a teacher in another classroom, don't add them to the list
        if (!teachers.any((e) => e.id == teacher.id) && userID != teacher.id) {
          teachers.add(teacher);
        }
      }
    }
    return teachers;
  }

  Future<Room> _getReportsDM(User teacher, Room space) async {
    final String roomId = await teacher.startDirectChat(
      enableEncryption: false,
    );
    space.setSpaceChild(
      roomId,
      suggested: false,
    );
    return getRoomById(roomId)!;
  }

  Future<bool> get _hasBotDM async {
    final List<Room> chats = rooms
        .where((room) => !room.isSpace && room.membership == Membership.join)
        .toList();

    for (final Room chat in chats) {
      if (await chat.isBotDM) return true;
    }
    return false;
  }

  Future<List<String>> _getEditHistory(
    String roomId,
    String eventId,
  ) async {
    final Room? room = getRoomById(roomId);
    final Event? editEvent = await room?.getEventById(eventId);
    final String? edittedEventId =
        editEvent?.content.tryGetMap('m.relates_to')?['event_id'];
    if (edittedEventId == null) return [];

    final Event? originalEvent = await room!.getEventById(edittedEventId);
    if (originalEvent == null) return [];

    final Timeline timeline = await room.getTimeline();
    final List<Event> editEvents = originalEvent
        .aggregatedEvents(
          timeline,
          RelationshipTypes.edit,
        )
        .sorted(
          (a, b) => b.originServerTs.compareTo(a.originServerTs),
        )
        .toList();
    editEvents.add(originalEvent);
    return editEvents.slice(1).map((e) => e.eventId).toList();
  }

  /// Returns a list of language models being learned by the users from a list of user ids.
  /// The list may not be complete if the logged in user is not in some of the
  /// user's analytics rooms. The list will be sorted by the number of
  /// users who are learning each language.
  List<LanguageModel> _targetLanguages({required List<String> userIDs}) {
    final Map<LanguageModel, int> langCounts = {};
    for (final Room room in rooms) {
      if (!room.isAnalyticsRoom ||
          room.creatorId == null ||
          room.madeForLang == null) {
        continue;
      }

      if (userIDs.contains(room.creatorId)) {
        final lang = PangeaLanguage.byLangCode(room.madeForLang!);
        langCounts[lang] ??= 0;
        langCounts[lang] = langCounts[lang]! + 1;
      }
    }

    // get a list of language models, sorted
    // by the number of students who are learning that language
    return langCounts.entries.map((entry) => entry.key).toList()
      ..sort(
        (a, b) => langCounts[b]!.compareTo(langCounts[a]!),
      );
  }

  String? _powerLevelName(int powerLevel, L10n l10n) => {
        0: l10n.user,
        50: l10n.moderator,
        100: l10n.admin,
      }[powerLevel];

  /// Account data comes through in the first sync, so wait for that
  Future<void> _waitForAccountData() async {
    if (prevBatch == null) {
      await onSync.stream.first;
    }
  }
}
