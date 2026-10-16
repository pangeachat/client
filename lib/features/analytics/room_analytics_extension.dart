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

  /// Sends [batches] of construct uses in order and reports which of them the
  /// server accepted.
  ///
  /// No pending copy is shown: nothing displays this room, and a pending copy
  /// reads as the server's on `onSync` and outlives a failed send (#9511).
  Future<ConstructsUploadResult> sendConstructsEvent(
    List<List<OneConstructUse>> batches,
  ) async {
    // It's possible that the user has no info to send yet, but to prevent trying
    // to load the data over and over again, we'll sometimes send an empty event to
    // indicate that we have checked and there was no data.
    if (batches.every((batch) => batch.isEmpty)) {
      final eventId = await _sendConstructUses([]);
      return ConstructsUploadResult(
        batchCount: batches.length,
        acceptedBatchCount: eventId == null ? 0 : batches.length,
        partlyAcceptedUseCount: 0,
        acceptedEventIds: [?eventId],
      );
    }

    final acceptedEventIds = <String>[];
    var acceptedBatchCount = 0;
    var partlyAcceptedUseCount = 0;
    for (final event in PackedConstructEvent.pack(batches)) {
      final eventId = await _sendConstructUses(event.uses);
      // The events after a refused one would most likely be refused too, and
      // each refusal costs the SDK's full send timeout.
      if (eventId == null) break;
      acceptedEventIds.add(eventId);
      acceptedBatchCount = event.completedBatchCount;
      partlyAcceptedUseCount = event.sentUsesOfSplitBatch;

      // Send-then-POST: the Matrix write is already durable; now best-effort
      // dual-write this batch to the teacher-BFF under its REAL event id. This
      // is a no-op unless the feature is enabled + a BFF URL is configured, and
      // it never throws — a failure is swallowed and cannot affect this flow.
      _dualWriteConstructUses(eventId, event.uses);
    }

    return ConstructsUploadResult(
      batchCount: batches.length,
      acceptedBatchCount: acceptedBatchCount,
      partlyAcceptedUseCount: partlyAcceptedUseCount,
      acceptedEventIds: acceptedEventIds,
    );
  }

  /// The id the server gave the event, or null when it did not accept it.
  ///
  /// The SDK returns null for most refusals but throws for a few (`M_FORBIDDEN`,
  /// an event over its size limit). Those are caught here so that an upload
  /// still reports the events accepted before the refused one.
  Future<String?> _sendConstructUses(List<OneConstructUse> uses) async {
    try {
      return await sendEvent(
        ConstructAnalyticsModel(uses: uses).toJson(),
        type: PangeaEventTypes.construct,
        displayPendingEvent: false,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"roomId": id, "useCount": uses.length},
      );
      return null;
    }
  }

  /// Fire-and-forget the best-effort analytics dual-write for one sent batch.
  ///
  /// Deliberately NOT awaited: the construct event is already written to Matrix
  /// (the durable source of truth), so the dual-write is a pure side-channel and
  /// must not add latency or failure surface to [sendConstructsEvent]. The repo
  /// never throws; this only guards the pre-condition (a self-owned analytics
  /// room) before firing.
  void _dualWriteConstructUses(String eventId, List<OneConstructUse> chunk) {
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
