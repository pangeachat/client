part of "../extensions/pangea_room_extension.dart";

extension AnalyticsRoomExtension on Room {
  String? get madeForLang {
    final creationContent = getState(EventTypes.RoomCreate)?.content;
    return creationContent?.tryGet<String>(ModelKey.langCode) ??
        creationContent?.tryGet<String>(ModelKey.oldLangCode);
  }

  bool isMadeForLang(String langCode) {
    final creationContent = getState(EventTypes.RoomCreate)?.content;
    return creationContent?.tryGet<String>(ModelKey.langCode) == langCode ||
        creationContent?.tryGet<String>(ModelKey.oldLangCode) == langCode;
  }

  Future<List<ConstructAnalyticsEvent>?> getAnalyticsEvents({
    required String userId,
    DateTime? since,
  }) async {
    final events = await getRoomAnalyticsEvents(userID: userId);
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
      await sendEvent(
        constructsModel.toJson(),
        type: PangeaEventTypes.construct,
      );
    }
  }
}
