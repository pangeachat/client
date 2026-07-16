part of "../../pangea/extensions/pangea_room_extension.dart";

extension AnalyticsRoomExtension on Room {
  bool get isAnalyticsRoom => roomType == PangeaRoomTypes.analytics;

  String? get madeForLang {
    final creationContent = getState(EventTypes.RoomCreate)?.content;
    return creationContent?.tryGet<String>(ModelKey.langCode) ??
        creationContent?.tryGet<String>(ModelKey.oldLangCode);
  }

  bool _isMadeForLang(String langCode) {
    final creationContent = getState(EventTypes.RoomCreate)?.content;
    return creationContent?.tryGet<String>(ModelKey.langCode) == langCode ||
        creationContent?.tryGet<String>(ModelKey.oldLangCode) == langCode;
  }

  bool isAnalyticsRoomOfUser(String userId) =>
      isAnalyticsRoom && isMadeByUser(userId) && analyticsStatus.isCanonical;

  bool isAnalyticsRoomOfUserForLanguage({
    required String userID,
    required LanguageModel lang,
  }) => isAnalyticsRoomOfUser(userID) && _isMadeForLang(lang.langCodeShort);

  Future<List<ConstructAnalyticsEvent>?> getAnalyticsEvents({
    required String userId,
    DateTime? since,
  }) async {
    final events = await getRoomAnalyticsEvents(userID: userId, since: since);
    final List<ConstructAnalyticsEvent> analyticsEvents = [];
    for (final Event event in events) {
      analyticsEvents.add(ConstructAnalyticsEvent(event: event));
    }

    return analyticsEvents;
  }

  /// Sends construct events to the server.
  ///
  /// The [uses] parameter is a list of [OneConstructUse] objects representing the
  /// constructs to be sent. To prevent hitting the maximum event size, the events
  /// are chunked into smaller lists. Each chunk is sent as a separate event.
  Future<void> sendConstructsEvent(List<OneConstructUse> uses) async {
    // It's possible that the user has no info to send yet, but to prevent trying
    // to load the data over and over again, we'll sometimes send an empty event to
    // indicate that we have checked and there was no data.
    if (uses.isEmpty) {
      final constructsModel = ConstructAnalyticsModel(uses: []);
      await sendEvent(
        constructsModel.toJson(),
        type: PangeaEventTypes.construct,
      );
      return;
    }

    // these events can get big, so we chunk them to prevent hitting the max event size.
    // go through each of the uses being sent and add them to the current chunk until
    // the size (in bytes) of the current chunk is greater than the max event size, then
    // start a new chunk until all uses have been added.
    final List<List<OneConstructUse>> useChunks = [];
    List<OneConstructUse> currentChunk = [];
    int currentChunkSize = 0;

    for (final use in uses) {
      // get the size, in bytes, of the json representation of the use
      final json = use.toJson();
      final jsonString = jsonEncode(json);
      final jsonSizeInBytes = utf8.encode(jsonString).length;

      // If this use would tip this chunk over the size limit,
      // add it to the list of all chunks and start a new chunk.
      //
      // I tested with using the maxPDUSize constant, but the events
      // were still too large. 50000 seems to be a safe number of bytes.
      if (currentChunkSize + jsonSizeInBytes > (maxPDUSize - 10000)) {
        useChunks.add(currentChunk);
        currentChunk = [];
        currentChunkSize = 0;
      }

      // add this use to the current chunk
      currentChunk.add(use);
      currentChunkSize += jsonSizeInBytes;
    }

    if (currentChunk.isNotEmpty) {
      useChunks.add(currentChunk);
    }

    for (final chunk in useChunks) {
      final constructsModel = ConstructAnalyticsModel(uses: chunk);
      final String? eventId = await sendEvent(
        constructsModel.toJson(),
        type: PangeaEventTypes.construct,
      );

      // Send-then-POST: the Matrix write is already durable; now best-effort
      // dual-write this batch to the teacher-BFF under its REAL event id. This
      // is a no-op unless the feature is enabled + a BFF URL is configured, and
      // it never throws — a failure is swallowed and cannot affect this flow.
      _dualWriteConstructUses(eventId, chunk);
    }
  }

  /// Fire-and-forget the best-effort analytics dual-write for one sent batch.
  ///
  /// Deliberately NOT awaited: the construct event is already written to Matrix
  /// (the durable source of truth), so the dual-write is a pure side-channel and
  /// must not add latency or failure surface to [sendConstructsEvent]. The repo
  /// never throws; this only guards the pre-conditions (a resolved event id and
  /// a self-owned analytics room) before firing.
  void _dualWriteConstructUses(String? eventId, List<OneConstructUse> chunk) {
    // A null id means sendEvent could not resolve one (e.g. offline queue); the
    // server rejects blank/placeholder ids, so skip rather than post a bad one.
    if (eventId == null || eventId.isEmpty) return;
    // The endpoint's ownership check requires the caller to be the analytics
    // room creator; only dual-write our OWN analytics room.
    if (!isAnalyticsRoomOfUser(client.userID ?? "")) return;

    // Defer the ENTIRE dual-write onto the event loop. `unawaited` alone would
    // still run postConstructUses synchronously up to its first `await` (the env
    // reads + `jsonEncode` of a near-max chunk) INSIDE sendConstructsEvent,
    // adding latency between Matrix sends for a large backlog. Wrapping in
    // `Future(...)` schedules all of that work off the current stack; the
    // trailing `.catchError` is belt-and-suspenders (the repo never throws).
    unawaited(
      Future<void>(() async {
        await AnalyticsEventsRepo.postConstructUses(
          analyticsRoomId: id,
          matrixEventId: eventId,
          uses: chunk,
          accessToken: client.accessToken,
        );
      }).catchError((_) {}),
    );
  }
}
