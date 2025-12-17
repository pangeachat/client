// import 'dart:async';

// import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
// import 'package:fluffychat/widgets/matrix.dart';

// /// A minimized version of AnalyticsController that get the logged in user's analytics
// class GetAnalyticsController {
//   // static final GetStorage analyticsBox = GetStorage("analytics_storage");
//   // late PracticeSelectionRepo perMessage;

//   // final List<AnalyticsCacheEntry> _cache = [];
//   // StreamController<AnalyticsStreamUpdate> analyticsStream =
//   //     StreamController.broadcast();

//   // // ConstructListModel constructListModel = ConstructListModel(uses: []);
//   // Completer<void> initCompleter = Completer<void>();
//   // bool _initializing = false;

//   GetAnalyticsController();

//   Future<void> onAnalyticsUpdate(
//     AnalyticsUpdate analyticsUpdate,
//   ) async {
//     // if (analyticsUpdate.isLogout) return;
//     // final analyticsService =
//     MatrixState.pangeaController.matrixState.analyticsDataService.updateService
//         .onConstructAnalyticsUpdate(analyticsUpdate);
//     // if (analyticsService == null) return;

//     // // final offset =
//     // //     _pangeaController.userController.analyticsProfile?.xpOffset ?? 0;

//     // final morphIds = analyticsUpdate.newConstructs
//     //     .where((c) => c.constructType == ConstructTypeEnum.morph)
//     //     .map((c) => c.identifier)
//     //     .toSet();

//     // final prevData = await analyticsService.derivedData;
//     // final oldLevel = prevData.level;

//     // final prevMorphs =
//     //     await analyticsService.getConstructUses(morphIds.toList());

//     // // constructListModel.updateConstructs(analyticsUpdate.newConstructs, offset);
//     // if (analyticsUpdate.type == AnalyticsUpdateType.local) {
//     //   await analyticsService.updateLocalAnalytics(analyticsUpdate);
//     // }

//     // final newMorphs =
//     //     await analyticsService.getConstructUses(morphIds.toList());

//     // final newUnlockedMorphs = morphIds.where((id) {
//     //   final prevPoints = prevMorphs[id]?.points ?? 0;
//     //   final newPoints = newMorphs[id]?.points ?? 0;
//     //   return prevPoints < 30 && newPoints >= 30;
//     // }).toSet();

//     // // if (analyticsUpdate.type == AnalyticsUpdateType.server) {
//     // //   await _getConstructs(forceUpdate: true);
//     // // }

//     // final data = await analyticsService.derivedData;
//     // if (oldLevel < data.level) {
//     //   // do not await this - it's not necessary for this to finish
//     //   // before the function completes and it blocks the UI
//     //   _onLevelUp(oldLevel, data.level);
//     // }
//     // if (oldLevel > data.level) {
//     //   await _onLevelDown(data.level, oldLevel, data.totalXP);
//     // }
//     // if (newUnlockedMorphs.isNotEmpty) {
//     //   _onUnlockMorphLemmas(newUnlockedMorphs);
//     // }
//     // _updateAnalyticsStream(
//     //   AnalyticsStreamUpdate(
//     //     points: analyticsUpdate.newConstructs.fold<int>(
//     //       0,
//     //       (previousValue, element) => previousValue + element.xp,
//     //     ),
//     //     targetID: analyticsUpdate.targetID,
//     //   ),
//     // );
//     // // Update public profile each time that new analytics are added.
//     // // If the level hasn't changed, this will not send an update to the server.
//     // // Do this on all updates (not just on level updates) to account for cases
//     // // of target language updates being missed (https://github.com/pangeachat/client/issues/2006)
//     // MatrixState.pangeaController.userController.updateAnalyticsProfile(
//     //   level: data.level,
//     // );
//   }

//   // void _updateAnalyticsStream(AnalyticsStreamUpdate update) =>
//   //     analyticsStream.add(update);

//   // void _onLevelUp(final int lowerLevel, final int upperLevel) {
//   //   setState({
//   //     'level_up': upperLevel,
//   //     'upper_level': upperLevel,
//   //     'lower_level': lowerLevel,
//   //   });
//   // }

//   // Future<void> _onLevelDown(
//   //   final int lowerLevel,
//   //   final int upperLevel,
//   //   final int totalXP,
//   // ) async {
//   //   final offset =
//   //       DerivedAnalyticsDataModel.calculateXpWithLevel(lowerLevel) - totalXP;
//   //   await MatrixState.pangeaController.userController.addXPOffset(offset);
//   //   final newOffset =
//   //       MatrixState.pangeaController.userController.analyticsProfile!.xpOffset!;

//   //   MatrixState.pangeaController.matrixState.analyticsDataService
//   //       ?.updateXPOffset(
//   //     newOffset,
//   //   );
//   // }

//   // void _onUnlockMorphLemmas(Set<ConstructIdentifier> unlocked) {
//   //   const excludedLemmas = {'not_proper'};

//   //   final filtered = {
//   //     for (final id in unlocked)
//   //       if (!excludedLemmas.contains(id.lemma.toLowerCase())) id,
//   //   };

//   //   setState({'unlocked_constructs': filtered});
//   // }

//   // void onActivityAnalyticsUpdate() =>
//   //     _updateAnalyticsStream(AnalyticsStreamUpdate());

//   // void onBlockedConstructsUpdate(ConstructIdentifier constructId) {
//   // constructListModel.deleteConstruct(
//   //   constructId,
//   //   _pangeaController.userController.analyticsProfile?.xpOffset ?? 0,
//   // );
//   // _updateAnalyticsStream(AnalyticsStreamUpdate());
//   // }

//   // LanguageModel? get _l1 => MatrixState.pangeaController.userController.userL1;
//   // LanguageModel? get _l2 => MatrixState.pangeaController.userController.userL2;

//   // Client get _client => MatrixState.pangeaController.matrixState.client;

//   // Future<void> initialize() async {
//   //   if (_initializing || initCompleter.isCompleted) return;
//   //   _initializing = true;

//   //   try {
//   //     _client.updateAnalyticsRoomJoinRules();
//   //     _client.addAnalyticsRoomsToSpaces();

//   //     // await _pangeaController.putAnalytics.lastUpdatedCompleter.future;
//   //     // await _getConstructs();

//   //     // final offset =
//   //     //     _pangeaController.userController.analyticsProfile?.xpOffset ?? 0;

//   //     // final allUses = [
//   //     //   ...(_getConstructsLocal() ?? []),
//   //     //   ..._locallyCachedConstructs,
//   //     // ];

//   //     // final Room? analyticsRoom = _client.analyticsRoomLocal(_l2!);
//   //     // final blockedLemmas = analyticsRoom?.analyticsSettings?.blockedConstructs;
//   //     // if (blockedLemmas != null && blockedLemmas.isNotEmpty) {
//   //     //   allUses.removeWhere(
//   //     //     (use) => blockedLemmas.contains(use.identifier),
//   //     //   );
//   //     // }

//   //     // constructListModel.updateConstructs(
//   //     //   [
//   //     //     ...(_getConstructsLocal() ?? []),
//   //     //     ..._locallyCachedConstructs,
//   //     //   ],
//   //     //   offset,
//   //     // );
//   //   } catch (err, s) {
//   //     ErrorHandler.logError(
//   //       e: err,
//   //       s: s,
//   //       data: {},
//   //     );
//   //   } finally {
//   //     _updateAnalyticsStream(AnalyticsStreamUpdate());
//   //     if (!initCompleter.isCompleted) initCompleter.complete();
//   //     _initializing = false;
//   //   }
//   // }

//   // List<Room> get archivedActivities {
//   //   final client = MatrixState.pangeaController.matrixState.client;
//   // final Room? analyticsRoom = client.analyticsRoomLocal(
//   //   MatrixState.pangeaController.userController.userL2!,
//   // );
//   //   if (analyticsRoom == null) return [];
//   //   final ids = analyticsRoom.activityRoomIds;
//   //   return ids
//   //       .map((id) => client.getRoomById(id))
//   //       .whereType<Room>()
//   //       .where(
//   //         (room) =>
//   //             room.membership != Membership.leave &&
//   //             room.membership != Membership.ban,
//   //       )
//   //       .toList();
//   // }

//   // int get archivedActivitiesCount {
//   //   return archivedActivities.length;
//   // }

//   // /// A local cache of eventIds and construct uses for messages sent since the last update.
//   // /// It's a map of eventIDs to a list of OneConstructUses. Not just a list of OneConstructUses
//   // /// because, with practice activity constructs, we might need to add to the list for a given
//   // /// eventID.
//   // Map<String, List<OneConstructUse>> get messagesSinceUpdate {
//   //   try {
//   //     final dynamic locallySaved = analyticsBox.read(
//   //       PLocalKey.messagesSinceUpdate,
//   //     );
//   //     if (locallySaved == null) return {};
//   //     try {
//   //       // try to get the local cache of messages and format them as OneConstructUses
//   //       final Map<String, List<dynamic>> cache =
//   //           Map<String, List<dynamic>>.from(locallySaved);
//   //       final Map<String, List<OneConstructUse>> formattedCache = {};
//   //       for (final entry in cache.entries) {
//   //         try {
//   //           formattedCache[entry.key] =
//   //               entry.value.map((e) => OneConstructUse.fromJson(e)).toList();
//   //         } catch (err, s) {
//   //           ErrorHandler.logError(
//   //             e: err,
//   //             s: s,
//   //             data: {
//   //               "key": entry.key,
//   //             },
//   //           );
//   //           continue;
//   //         }
//   //       }
//   //       return formattedCache;
//   //     } catch (err) {
//   //       // if something goes wrong while trying to format the local data, clear it
//   //       clearMessagesCache();
//   //       return {};
//   //     }
//   //   } catch (exception, stackTrace) {
//   //     ErrorHandler.logError(
//   //       e: PangeaWarningError(
//   //         "Failed to get messages since update: $exception",
//   //       ),
//   //       s: stackTrace,
//   //       m: 'Failed to retrieve messages since update',
//   //       data: {
//   //         "messagesSinceUpdate": PLocalKey.messagesSinceUpdate,
//   //       },
//   //     );
//   //     return {};
//   //   }
//   // }

//   // Future<void> clearMessagesCache() async =>
//   //     analyticsBox.remove(PLocalKey.messagesSinceUpdate);

//   // Future<void> setMessagesCache(Map<dynamic, dynamic> cacheValue) async =>
//   //     analyticsBox.write(
//   //       PLocalKey.messagesSinceUpdate,
//   //       cacheValue,
//   //     );

//   // /// A flat list of all locally cached construct uses
//   // List<OneConstructUse> get _locallyCachedConstructs =>
//   //     messagesSinceUpdate.values.expand((e) => e).toList();

//   // /// A flat list of all locally cached construct uses that are not drafts
//   // List<OneConstructUse> get locallyCachedSentConstructs =>
//   //     messagesSinceUpdate.entries
//   //         .where((entry) => !entry.key.startsWith('draft'))
//   //         .expand((e) => e.value)
//   //         .toList();

//   // /// Get a list of all constructs used by the logged in user in their current L2
//   // Future<List<OneConstructUse>> _getConstructs({
//   //   bool forceUpdate = false,
//   //   ConstructTypeEnum? constructType,
//   // }) async {
//   //   // if the user isn't logged in, return an empty list
//   //   if (_client.userID == null) return [];
//   //   if (_client.prevBatch == null) {
//   //     await _client.onSync.stream.first;
//   //   }

//   //   // don't try to get constructs until last updated time has been loaded
//   //   await _pangeaController.putAnalytics.lastUpdatedCompleter.future;

//   //   // if forcing a refreshing, clear the cache
//   //   if (forceUpdate) _cache.clear();

//   //   final List<OneConstructUse>? local = _getConstructsLocal(
//   //     constructType: constructType,
//   //   );

//   //   if (local != null) {
//   //     debugPrint("returning local constructs");
//   //     return local;
//   //   }
//   //   debugPrint("fetching new constructs");

//   //   // if there is no cached data (or if force updating),
//   //   // get all the construct events for the user from analytics room
//   //   // and convert their content into a list of construct uses
//   //   final List<ConstructAnalyticsEvent> constructEvents =
//   //       await _allMyConstructs();

//   //   final List<OneConstructUse> uses = [];
//   //   for (final event in constructEvents) {
//   //     uses.addAll(event.content.uses);
//   //   }

//   //   // if there isn't already a valid, local cache, cache the filtered uses
//   //   if (local == null) {
//   //     _cacheConstructs(
//   //       constructType: constructType,
//   //       uses: uses,
//   //     );
//   //   }

//   //   return uses;
//   // }

//   // /// Get the last time the user updated their analytics for their current l2
//   // Future<DateTime?> myAnalyticsLastUpdated() async {
//   //   // this function gets called soon after login, so first
//   //   // make sure that the user's l2 is loaded, if the user has set their l2
//   //   if (_client.userID != null && _l2 == null) {
//   //     if (_client.prevBatch == null) {
//   //       await _client.onSync.stream.first;
//   //     }
//   //     if (_l2 == null) return null;
//   //   }
//   //   final Room? analyticsRoom = _client.analyticsRoomLocal(_l2!);
//   //   if (analyticsRoom == null) return null;
//   //   final DateTime? lastUpdated = await analyticsRoom.analyticsLastUpdated(
//   //     _client.userID!,
//   //   );
//   //   return lastUpdated;
//   // }

//   // /// Get all the construct analytics events for the logged in user
//   // Future<List<ConstructAnalyticsEvent>> _allMyConstructs() async {
//   //   if (_l2 == null) return [];
//   //   final Room? analyticsRoom = _client.analyticsRoomLocal(_l2!);
//   //   if (analyticsRoom == null) return [];
//   //   return await analyticsRoom.getAnalyticsEvents(userId: _client.userID!) ??
//   //       [];
//   // }

//   // /// Get the cached construct uses for the current user, if it exists
//   // List<OneConstructUse>? _getConstructsLocal({
//   //   ConstructTypeEnum? constructType,
//   // }) {
//   //   final index = _cache.indexWhere(
//   //     (e) => e.type == constructType && e.langCode == _l2?.langCodeShort,
//   //   );

//   //   if (index > -1) {
//   //     final DateTime? lastUpdated = _pangeaController.putAnalytics.lastUpdated;
//   //     if (_cache[index].needsUpdate(lastUpdated)) {
//   //       _cache.removeAt(index);
//   //       return null;
//   //     }
//   //     return _cache[index].uses;
//   //   }

//   //   return null;
//   // }

//   // /// Cache the construct uses for the current user
//   // void _cacheConstructs({
//   //   required List<OneConstructUse> uses,
//   //   ConstructTypeEnum? constructType,
//   // }) {
//   //   if (_l2 == null) return;
//   //   final entry = AnalyticsCacheEntry(
//   //     type: constructType,
//   //     uses: List.from(uses),
//   //     langCode: _l2!.langCodeShort,
//   //   );
//   //   _cache.add(entry);
//   // }

//   // Future<String> _saveConstructSummaryResponseToStateEvent(
//   //   final ConstructSummary summary,
//   // ) async {
//   //   final Room? analyticsRoom = _client.analyticsRoomLocal(_l2!);
//   //   final stateEventId = await _client.setRoomStateWithKey(
//   //     analyticsRoom!.id,
//   //     PangeaEventTypes.constructSummary,
//   //     '',
//   //     summary.toJson(),
//   //   );
//   //   return stateEventId;
//   // }

//   // Future<int> newConstructCount(
//   //   List<OneConstructUse> newConstructs,
//   //   ConstructTypeEnum type,
//   // ) async {
//   //   final analyticsService = _pangeaController.matrixState.analyticsDataService;
//   //   if (analyticsService == null) return 0;

//   //   final uses = newConstructs.where((c) => c.constructType == type);
//   //   final Map<ConstructIdentifier, int> constructPoints = {};
//   //   for (final use in uses) {
//   //     constructPoints[use.identifier] ??= 0;
//   //     constructPoints[use.identifier] =
//   //         constructPoints[use.identifier]! + use.xp;
//   //   }

//   //   int newConstructCount = 0;
//   //   for (final entry in constructPoints.entries) {
//   //     final construct = await analyticsService.getConstructUse(entry.key);
//   //     if (construct.points == entry.value) {
//   //       newConstructCount++;
//   //     }
//   //   }

//   //   return newConstructCount;
//   // }

//   // ConstructSummary? getConstructSummaryFromStateEvent() {
//   //   try {
//   //     final Room? analyticsRoom = _client.analyticsRoomLocal(_l2!);
//   //     if (analyticsRoom == null) {
//   //       debugPrint("Analytics room is null");
//   //       return null;
//   //     }
//   //     final state =
//   //         analyticsRoom.getState(PangeaEventTypes.constructSummary, '');
//   //     if (state == null) return null;
//   //     return ConstructSummary.fromJson(state.content);
//   //   } catch (e) {
//   //     debugPrint("Error getting construct summary room: $e");
//   //     ErrorHandler.logError(e: e, data: {'e': e});
//   //     return null;
//   //   }
//   // }

//   // Future<ConstructSummary> generateLevelUpAnalytics(
//   //   final int lowerLevel,
//   //   final int upperLevel,
//   // ) async {
//   //   final analyticsService = _pangeaController.matrixState.analyticsDataService;
//   //   if (analyticsService == null) {
//   //     throw "Analytics service is not initialized";
//   //   }

//   //   final int maxXP =
//   //       DerivedAnalyticsDataModel.calculateXpWithLevel(upperLevel);
//   //   final int minXP =
//   //       DerivedAnalyticsDataModel.calculateXpWithLevel(lowerLevel);

//   //   int diffXP = maxXP - minXP;
//   //   if (diffXP < 0) diffXP = 0;

//   //   // compute construct use of current level
//   //   final List<OneConstructUse> constructUseOfCurrentLevel = [];

//   //   final data = await analyticsService.derivedData;
//   //   final int score = data.totalXP;
//   //   // for (final use in constructListModel.uses) {
//   //   //   constructUseOfCurrentLevel.add(use);
//   //   //   score -= use.xp;
//   //   //   if (score <= minXP) break;
//   //   // }

//   //   // extract construct use message bodies for analytics
//   //   final Map<String, Set<String>> useEventIds = {};
//   //   for (final use in constructUseOfCurrentLevel) {
//   //     if (use.metadata.roomId == null) continue;
//   //     if (use.metadata.eventId == null) continue;
//   //     useEventIds[use.metadata.roomId!] ??= {};
//   //     useEventIds[use.metadata.roomId!]!.add(use.metadata.eventId!);
//   //   }

//   //   final List<Map<String, dynamic>> messages = [];
//   //   for (final entry in useEventIds.entries) {
//   //     final String roomId = entry.key;
//   //     final room = _client.getRoomById(roomId);
//   //     if (room == null) continue;

//   //     final timeline = await room.getTimeline();
//   //     for (final eventId in entry.value) {
//   //       try {
//   //         final Event? event = await room.getEventById(eventId);
//   //         if (event == null) continue;
//   //         final pangeaMessageEvent = PangeaMessageEvent(
//   //           event: event,
//   //           timeline: timeline,
//   //           ownMessage: room.client.userID == event.senderId,
//   //         );

//   //         final Map<String, String?> entry = {
//   //           "sent": pangeaMessageEvent.originalSent?.text ??
//   //               pangeaMessageEvent.body,
//   //           "written": pangeaMessageEvent.originalWrittenContent,
//   //         };

//   //         messages.add(entry);
//   //       } catch (e, s) {
//   //         debugPrint("Error getting event by ID: $e");
//   //         ErrorHandler.logError(
//   //           e: e,
//   //           s: s,
//   //           data: {
//   //             'roomId': roomId,
//   //             'eventId': eventId,
//   //           },
//   //         );
//   //         continue;
//   //       }
//   //     }
//   //   }

//   //   final request = ConstructSummaryRequest(
//   //     constructs: constructUseOfCurrentLevel,
//   //     messages: messages,
//   //     userL1: _l1!.langCodeShort,
//   //     userL2: _l2!.langCodeShort,
//   //     upperLevel: upperLevel,
//   //     lowerLevel: lowerLevel,
//   //   );

//   //   final response = await ConstructRepo.generateConstructSummary(request);
//   //   final ConstructSummary summary = response.summary;
//   //   summary.levelVocabConstructs = MatrixState
//   //       .pangeaController.matrixState.analyticsDataService
//   //       ?.numConstructs(ConstructTypeEnum.vocab);
//   //   summary.levelGrammarConstructs = MatrixState
//   //       .pangeaController.matrixState.analyticsDataService
//   //       ?.numConstructs(ConstructTypeEnum.morph);

//   //   final Room? analyticsRoom = await _client.getMyAnalyticsRoom(_l2!);
//   //   if (analyticsRoom == null) {
//   //     throw "Analytics room not found for user";
//   //   }

//   //   // don't await this, just return the original response
//   //   analyticsRoom.setLevelUpSummary(summary);
//   //   return summary;
//   // }
// }
