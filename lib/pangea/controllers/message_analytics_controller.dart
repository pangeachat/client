import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:fluffychat/pangea/constants/match_rule_ids.dart';
import 'package:fluffychat/pangea/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/controllers/language_list_controller.dart';
import 'package:fluffychat/pangea/enum/construct_type_enum.dart';
import 'package:fluffychat/pangea/enum/time_span.dart';
import 'package:fluffychat/pangea/models/analytics/analytics_event.dart';
import 'package:fluffychat/pangea/models/analytics/constructs_event.dart';
import 'package:fluffychat/pangea/models/analytics/summary_analytics_event.dart';
import 'package:fluffychat/pangea/models/language_model.dart';
import 'package:fluffychat/pangea/pages/analytics/base_analytics.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../constants/class_default_values.dart';
import '../extensions/client_extension/client_extension.dart';
import '../extensions/pangea_room_extension/pangea_room_extension.dart';
import '../models/analytics/chart_analytics_model.dart';
import 'base_controller.dart';
import 'pangea_controller.dart';

/// Controls the fetching of analytics data from analytics rooms.
/// Manages filtering and caching. Currently, analytics
/// data includes summary analytics and construct analytics.
class AnalyticsController extends BaseController {
  late PangeaController _pangeaController;
  final List<AnalyticsCacheModel> _cachedAnalyticsModels = [];
  final List<ConstructCacheEntry> _cachedConstructs = [];

  AnalyticsController(PangeaController pangeaController) : super() {
    _pangeaController = pangeaController;
  }

  /** Time Span Management **/

  /// Key for locally cached analytics time span
  String get _analyticsTimeSpanKey => "ANALYTICS_TIME_SPAN_KEY";

  /// Get the current analytics time span from local storage.
  /// If not present, returns the default time span.
  TimeSpan get currentAnalyticsTimeSpan {
    try {
      final String? str = _pangeaController.pStoreService.read(
        _analyticsTimeSpanKey,
      );
      return str != null
          ? TimeSpan.values.firstWhere((e) {
              final spanString = e.toString();
              return spanString == str;
            })
          : ClassDefaultValues.defaultTimeSpan;
    } catch (err) {
      debugger(when: kDebugMode);
      return ClassDefaultValues.defaultTimeSpan;
    }
  }

  /// Sets the current analytics time span in local storage.
  Future<void> setCurrentAnalyticsTimeSpan(TimeSpan timeSpan) async {
    await _pangeaController.pStoreService.save(
      _analyticsTimeSpanKey,
      timeSpan.toString(),
    );
    setState();
  }

  /** Current Language Management **/

  /// Key for locally cached analytics language
  String get _analyticsSpaceLangKey => "ANALYTICS_SPACE_LANG_KEY";

  /// Get the current analytics language from local storage.
  LanguageModel get currentAnalyticsLang {
    try {
      final String? str = _pangeaController.pStoreService.read(
        _analyticsSpaceLangKey,
      );
      return str != null
          ? PangeaLanguage.byLangCode(str)
          : _pangeaController.languageController.userL2 ??
              _pangeaController.pLanguageStore.targetOptions.first;
    } catch (err) {
      debugger(when: kDebugMode);
      return _pangeaController.pLanguageStore.targetOptions.first;
    }
  }

  /// Sets the current analytics language in local storage.
  Future<void> setCurrentAnalyticsLang(LanguageModel lang) async {
    await _pangeaController.pStoreService.save(
      _analyticsSpaceLangKey,
      lang.langCode,
    );
    setState();
  }

  /// Given an analytics event type, a userID, and the current analytics
  /// language, get the last time the user updated their analytics
  Future<DateTime?> userAnalyticsLastUpdated(
    String type, {
    String? userID,
  }) async {
    userID ??= _pangeaController.matrixState.client.userID;
    if (userID == null) return null;
    final Room? analyticsRoom = _pangeaController.matrixState.client
        .analyticsRoomLocal(currentAnalyticsLang.langCode, userID);
    return await analyticsRoom?.analyticsLastUpdated(type, userID);

    // final Map<String, DateTime> langCodeLastUpdates = {};
    // for (final Room analyticsRoom in analyticsRooms) {
    //   final String? roomLang = analyticsRoom.madeForLang;
    //   if (roomLang == null) continue;
    //   final DateTime? lastUpdated = await analyticsRoom.analyticsLastUpdated(
    //     type,
    //     userID,
    //   );
    //   if (lastUpdated != null) {
    //     langCodeLastUpdates[roomLang] = lastUpdated;
    //   }
    // }

    // if (langCodeLastUpdates.isEmpty) return null;
    // final String? l2Code =
    //     _pangeaController.languageController.userL2?.langCode;
    // if (l2Code != null && langCodeLastUpdates.containsKey(l2Code)) {
    //   return langCodeLastUpdates[l2Code];
    // }
    // return langCodeLastUpdates.values.reduce(
    //   (check, mostRecent) => check.isAfter(mostRecent) ? check : mostRecent,
    // );
  }

  /// Given an analytics event type and a room, get the most recent analytics
  /// update time. Used to check if any room members have recently updated
  /// their analytics. If any have, then the cache needs to be updated
  Future<DateTime?> participantAnalyticsLastUpdated(
    String type,
    Room room,
  ) async {
    // TODO - figure out how to do this on a per-user basis
    final List<Future<DateTime?>> lastUpdatedFutures = [];
    for (final student in room.getParticipants()) {
      final Room? analyticsRoom = _pangeaController.matrixState.client
          .analyticsRoomLocal(currentAnalyticsLang.langCode, student.id);
      if (analyticsRoom == null) continue;
      lastUpdatedFutures.add(
        analyticsRoom.analyticsLastUpdated(
          type,
          student.id,
        ),
      );
    }

    final List<DateTime?> lastUpdatedWithNulls =
        await Future.wait(lastUpdatedFutures);
    final List<DateTime> lastUpdates =
        lastUpdatedWithNulls.where((e) => e != null).cast<DateTime>().toList();
    if (lastUpdates.isNotEmpty) {
      return lastUpdates.reduce(
        (check, mostRecent) => check.isAfter(mostRecent) ? check : mostRecent,
      );
    }
    return null;
  }

  // Map of space ids to the last fetched hierarchy. Used when filtering
  // private chat analytics to determine which children are already visible
  // in the chat list
  final Map<String, GetSpaceHierarchyResponse> _lastFetchedHierarchies = {};

  Future<void> setLatestHierarchy(
    String spaceId,
  ) async {
    // If a hierarchy has already been loaded for this space, get it
    final GetSpaceHierarchyResponse? currentHierarchy =
        _lastFetchedHierarchies[spaceId];

    // if the hierarchy is already completely loaded, don't try to load more
    if (currentHierarchy != null && currentHierarchy.nextBatch == null) {
      return;
    }

    // load the next batch in the hierarchy and store it
    final resp = await _pangeaController.matrixState.client.getSpaceHierarchy(
      spaceId,
      from: currentHierarchy?.nextBatch,
    );
    resp.rooms.addAll(currentHierarchy?.rooms ?? []);
    _lastFetchedHierarchies[spaceId] = resp;
  }

  GetSpaceHierarchyResponse? getLatestSpaceHierarchy(String spaceId) {
    return _lastFetchedHierarchies[spaceId];
  }

  /// Get all the summary analytics events for a user
  /// in the current language's analytics room, since the
  /// current timespan's cut off date
  Future<List<SummaryAnalyticsEvent>> userSummaryAnalytics({
    required TimeSpan timeSpan,
    String? userID,
  }) async {
    userID ??= _pangeaController.matrixState.client.userID;
    final Room? analyticsRoom = _pangeaController.matrixState.client
        .analyticsRoomLocal(currentAnalyticsLang.langCode, userID);
    if (analyticsRoom == null) return [];

    final List<AnalyticsEvent>? roomEvents =
        await analyticsRoom.getAnalyticsEvents(
      type: PangeaEventTypes.summaryAnalytics,
      since: timeSpan.cutOffDate,
      userId: userID!,
    );
    return roomEvents?.cast<SummaryAnalyticsEvent>() ?? [];
  }

  /// Gets all the summary analytics events for the users
  /// in a room since the current timespan's cut off date
  Future<List<SummaryAnalyticsEvent>> roomMemberAnalytics(
    Room room,
    TimeSpan timeSpan,
  ) async {
    // TODO switch to using list of futures
    final List<SummaryAnalyticsEvent> analyticsEvents = [];
    for (final participant in room.getParticipants()) {
      final Room? analyticsRoom = _pangeaController.matrixState.client
          .analyticsRoomLocal(currentAnalyticsLang.langCode, participant.id);

      if (analyticsRoom != null) {
        final roomEvents = await analyticsRoom.getAnalyticsEvents(
          type: PangeaEventTypes.summaryAnalytics,
          since: timeSpan.cutOffDate,
          userId: participant.id,
        );
        analyticsEvents.addAll(
          roomEvents?.cast<SummaryAnalyticsEvent>() ?? [],
        );
      }
    }
    return analyticsEvents;
  }

  /// Gets all the summary analytics events for the users
  /// in a space since the current timespan's cut off date
  Future<List<SummaryAnalyticsEvent>> spaceMemberAnalytics(
    Room space,
    TimeSpan timeSpan,
  ) async {
    final memberEvents = await roomMemberAnalytics(space, timeSpan);
    final List<String> spaceChildrenIds = space.allSpaceChildRoomIds;

    // filter out the analyics events that don't belong to the space's children
    final List<SummaryAnalyticsEvent> allAnalyticsEvents = [];
    for (final analyticsEvent in memberEvents) {
      analyticsEvent.content.messages.removeWhere(
        (msg) => !spaceChildrenIds.contains(msg.chatId),
      );
      allAnalyticsEvents.add(analyticsEvent);
    }
    return allAnalyticsEvents;
  }

  /// Get an analytics model from the cache if it exists
  ChartAnalyticsModel? getAnalyticsLocal({
    required TimeSpan timeSpan,
    required AnalyticsSelected defaultSelected,
    AnalyticsSelected? selected,
    bool forceUpdate = false,
    bool updateExpired = false,
    DateTime? lastUpdated,
  }) {
    final int index = _cachedAnalyticsModels.indexWhere(
      (e) =>
          (e.timeSpan == timeSpan) &&
          (e.defaultSelected.id == defaultSelected.id) &&
          (e.defaultSelected.type == defaultSelected.type) &&
          (e.selected?.id == selected?.id) &&
          (e.selected?.type == selected?.type) &&
          (e.langCode == currentAnalyticsLang.langCode),
    );

    if (index != -1) {
      if ((updateExpired && _cachedAnalyticsModels[index].isExpired) ||
          forceUpdate ||
          _cachedAnalyticsModels[index].needsUpdate(lastUpdated)) {
        _cachedAnalyticsModels.removeAt(index);
      } else {
        return _cachedAnalyticsModels[index].chartAnalyticsModel;
      }
    }

    return null;
  }

  /// Cache an analytics model
  void cacheAnalytics({
    required ChartAnalyticsModel chartAnalyticsModel,
    required AnalyticsSelected defaultSelected,
    required TimeSpan timeSpan,
    AnalyticsSelected? selected,
  }) {
    _cachedAnalyticsModels.add(
      AnalyticsCacheModel(
        timeSpan: timeSpan,
        chartAnalyticsModel: chartAnalyticsModel,
        defaultSelected: defaultSelected,
        selected: selected,
        langCode: currentAnalyticsLang.langCode,
      ),
    );
  }

  /// Given a list of analytics events for the members of a room and the
  /// id of that room, goes through the list of events and removes any
  /// messages records that are not assosiated with the given room id
  Future<List<SummaryAnalyticsEvent>> filterRoomAnalytics(
    List<SummaryAnalyticsEvent> unfiltered,
    String? roomID,
  ) async {
    List<SummaryAnalyticsEvent> filtered = [...unfiltered];
    Room? room;
    if (roomID != null) {
      room = _pangeaController.matrixState.client.getRoomById(roomID);
      if (room?.isSpace == true) {
        return await filterSpaceAnalytics(unfiltered, room!);
      }
    }

    filtered = filtered
        .where(
          (e) => (e.content).messages.any((u) => u.chatId == roomID),
        )
        .toList();
    filtered.forEachIndexed(
      (i, _) => (filtered[i].content).messages.removeWhere(
            (u) => u.chatId != roomID,
          ),
    );
    return filtered;
  }

  /// Given a list of analytics events for the members of a space and the
  /// space itself, goes through the list of events and removes any
  /// messages records that are not assosiated with private chats within the space
  Future<List<SummaryAnalyticsEvent>> filterPrivateChatAnalytics(
    List<SummaryAnalyticsEvent> unfiltered,
    Room space,
  ) async {
    final List<String> privateChatIds = space.allSpaceChildRoomIds;
    final List<String> lastFetched = getLatestSpaceHierarchy(space.id)
            ?.rooms
            .map((room) => room.roomId)
            .toList() ??
        [];
    for (final id in lastFetched) {
      privateChatIds.removeWhere((e) => e == id);
    }

    List<SummaryAnalyticsEvent> filtered =
        List<SummaryAnalyticsEvent>.from(unfiltered);
    filtered = filtered.where((e) {
      return (e.content).messages.any(
            (u) => privateChatIds.contains(u.chatId),
          );
    }).toList();
    filtered.forEachIndexed(
      (i, _) => (filtered[i].content).messages.removeWhere(
            (u) => !privateChatIds.contains(u.chatId),
          ),
    );
    return filtered;
  }

  /// Given a list of analytics events for the members of a space and the
  /// space itself, goes through the list of events and removes any
  /// messages records that are not assosiated with the space's children
  Future<List<SummaryAnalyticsEvent>> filterSpaceAnalytics(
    List<SummaryAnalyticsEvent> unfiltered,
    Room space,
  ) async {
    final List<String> chatIds = space.allSpaceChildRoomIds;
    List<SummaryAnalyticsEvent> filtered =
        List<SummaryAnalyticsEvent>.from(unfiltered);

    filtered = filtered
        .where(
          (e) => e.content.messages.any((u) => chatIds.contains(u.chatId)),
        )
        .toList();

    filtered.forEachIndexed(
      (i, _) => (filtered[i].content).messages.removeWhere(
            (u) => !chatIds.contains(u.chatId),
          ),
    );
    return filtered;
  }

  /// Given a list of analytics events that have already been filtered by an
  /// initial filter (i.e., a user, room, or space), further filter the list
  /// based on the current analytics time span and the selected
  /// filter (i.e., a user, room, space, or private chats) (This is/was used in
  /// the old analytics page to filter by room/user/space
  /// list tiles. Might be removed in the future.)
  Future<List<SummaryAnalyticsEvent>> filterAnalytics({
    required List<SummaryAnalyticsEvent> unfilteredAnalytics,
    required AnalyticsSelected defaultSelected,
    required TimeSpan timeSpan,
    Room? space,
    AnalyticsSelected? selected,
  }) async {
    for (int i = 0; i < unfilteredAnalytics.length; i++) {
      unfilteredAnalytics[i].content.messages.removeWhere(
            (record) => record.time.isBefore(
              timeSpan.cutOffDate,
            ),
          );
    }

    unfilteredAnalytics.removeWhere((e) => e.content.messages.isEmpty);

    switch (selected?.type) {
      case null:
        return unfilteredAnalytics;
      case AnalyticsEntryType.student:
        if (defaultSelected.type != AnalyticsEntryType.space) {
          throw Exception(
            "student filtering not available for default filter ${defaultSelected.type}",
          );
        }
        return unfilteredAnalytics;
      case AnalyticsEntryType.room:
        return filterRoomAnalytics(unfilteredAnalytics, selected?.id);
      case AnalyticsEntryType.privateChats:
        if (defaultSelected.type == AnalyticsEntryType.student) {
          throw "private chat filtering not available for user analytics";
        }
        if (space == null) {
          throw "space is null in filterAnalytics with selected type privateChats";
        }
        return await filterPrivateChatAnalytics(
          unfilteredAnalytics,
          space,
        );
      case AnalyticsEntryType.space:
        final Room? room =
            _pangeaController.matrixState.client.getRoomById(selected!.id);
        if (room == null) {
          throw Exception("space not found in filterSpaceAnalytics");
        }
        return await filterSpaceAnalytics(unfilteredAnalytics, room);
      default:
        throw Exception("invalid filter type - ${selected?.type}");
    }
  }

  /// A wrapper around the main getAnalytics function, convenient for getting
  /// analytics for a specific user, room, or space without additional filtering.
  Future<ChartAnalyticsModel> getAnalyticsById({
    required String id,
    required AnalyticsEntryType type,
    TimeSpan? timeSpan,
  }) async {
    debugPrint("get analytics new");
    return await getAnalytics(
      defaultSelected: AnalyticsSelected(id, type, ''),
      timeSpan: timeSpan,
    );
  }

  /// The main function for getting summary analytics. Takes a top-level filter
  /// (a user, room, or space), and an optional secondary filter (a user, room,
  /// space, or private chats). The function fetches the relevant analytics events
  /// (either from a cache or directly from analytics rooms),
  /// filters them based on the selected filters,
  /// and returns a ChartAnalyticsModel to be displayed.
  Future<ChartAnalyticsModel> getAnalytics({
    required AnalyticsSelected defaultSelected,
    AnalyticsSelected? selected,
    bool forceUpdate = false,
    TimeSpan? timeSpan,
  }) async {
    try {
      await _pangeaController.matrixState.client.roomsLoading;
      timeSpan ??= currentAnalyticsTimeSpan;

      // if the user is looking at room or space analytics, then fetch the space
      Room? room;
      if (defaultSelected.type == AnalyticsEntryType.space ||
          defaultSelected.type == AnalyticsEntryType.room) {
        room = _pangeaController.matrixState.client.getRoomById(
          defaultSelected.id,
        );
        await room?.postLoad();
        await room?.requestParticipants();
      }

      DateTime? lastUpdated;
      switch (defaultSelected.type) {
        case AnalyticsEntryType.student:
          lastUpdated = await userAnalyticsLastUpdated(
            PangeaEventTypes.summaryAnalytics,
            userID: defaultSelected.id,
          );
          break;
        case AnalyticsEntryType.room:
        case AnalyticsEntryType.space:
          lastUpdated = await participantAnalyticsLastUpdated(
            PangeaEventTypes.summaryAnalytics,
            room!,
          );
          break;
        default:
          throw Exception(
            "invalid defaultSelected type - ${defaultSelected.type}",
          );
      }

      final ChartAnalyticsModel? local = getAnalyticsLocal(
        defaultSelected: defaultSelected,
        selected: selected,
        forceUpdate: forceUpdate,
        lastUpdated: lastUpdated,
        timeSpan: timeSpan,
      );
      if (local != null && !forceUpdate) {
        debugPrint("returning local analytics");
        return local;
      }
      debugPrint("fetching new analytics");

      // get all the relevant summary analytics events for the current timespan
      List<SummaryAnalyticsEvent> summaryEvents;
      switch (defaultSelected.type) {
        case AnalyticsEntryType.student:
          summaryEvents = await userSummaryAnalytics(
            userID: defaultSelected.id,
            timeSpan: timeSpan,
          );
          break;
        case AnalyticsEntryType.room:
          summaryEvents = await roomMemberAnalytics(
            room!,
            timeSpan,
          );
          break;
        case AnalyticsEntryType.space:
          summaryEvents = await spaceMemberAnalytics(
            room!,
            timeSpan,
          );
          break;
        default:
          throw Exception(
            "invalid defaultSelected type - ${defaultSelected.type}",
          );
      }

      // filter out the analytics events based on filters the user has chosen
      final List<SummaryAnalyticsEvent> filteredAnalytics =
          await filterAnalytics(
        unfilteredAnalytics: summaryEvents,
        defaultSelected: defaultSelected,
        space: room,
        selected: selected,
        timeSpan: timeSpan,
      );

      // then create and return the model to be displayed
      final ChartAnalyticsModel newModel = ChartAnalyticsModel(
        timeSpan: timeSpan,
        msgs: filteredAnalytics
            .map((event) => event.content.messages)
            .expand((msgs) => msgs)
            .toList(),
      );

      cacheAnalytics(
        chartAnalyticsModel: newModel,
        defaultSelected: defaultSelected,
        selected: selected,
        timeSpan: timeSpan,
      );

      return newModel;
    } catch (err, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: err, s: s);
      return ChartAnalyticsModel(
        msgs: [],
        timeSpan: timeSpan ?? currentAnalyticsTimeSpan,
      );
    }
  }

  /// Get all the construct analytics events for a user, since the current
  /// timespan's cut off date, in the current language's analytics room
  Future<List<ConstructAnalyticsEvent>> allUserConstructs({
    required ConstructTypeEnum constructType,
    required TimeSpan timeSpan,
    String? userID,
  }) async {
    userID ??= _pangeaController.matrixState.client.userID;
    final Room? analyticsRoom = _pangeaController.matrixState.client
        .analyticsRoomLocal(currentAnalyticsLang.langCode, userID);
    if (analyticsRoom == null) return [];

    final List<ConstructAnalyticsEvent>? roomEvents =
        (await analyticsRoom.getAnalyticsEvents(
      type: PangeaEventTypes.construct,
      since: timeSpan.cutOffDate,
      userId: userID!,
    ))
            ?.cast<ConstructAnalyticsEvent>();
    final List<ConstructAnalyticsEvent> allConstructs = roomEvents ?? [];

    // final List<String> adminSpaceRooms =
    //     await _pangeaController.matrixState.client.teacherRoomIds;
    // for (final construct in allConstructs) {
    //   construct.content.uses.removeWhere(
    //     (use) =>
    //         // filter out data from rooms in which the user is a teacher
    //         // commenting this out for now.
    //         // adminSpaceRooms.contains(use.chatId) ||
    //         use.constructType != constructType,
    //   );
    // }

    return allConstructs
        .where((construct) => construct.content.uses.isNotEmpty)
        .toList();
  }

  /// Get all the construct analytics events for the members of a room, of the specified type
  /// since the current timespan's cut off date, in the current language
  Future<List<ConstructAnalyticsEvent>> allRoomMemberConstructs(
    Room room,
    ConstructTypeEnum constructType,
    TimeSpan timeSpan,
  ) async {
    final List<ConstructAnalyticsEvent> constructEvents = [];
    for (final student in room.nonAdminsLocal) {
      final Room? analyticsRoom = _pangeaController.matrixState.client
          .analyticsRoomLocal(currentAnalyticsLang.langCode, student.id);
      if (analyticsRoom != null) {
        final List<ConstructAnalyticsEvent>? roomEvents =
            (await analyticsRoom.getAnalyticsEvents(
          type: PangeaEventTypes.construct,
          since: timeSpan.cutOffDate,
          userId: student.id,
        ))
                ?.cast<ConstructAnalyticsEvent>();
        constructEvents.addAll(roomEvents ?? []);
      }
    }

    // for (final construct in constructEvents) {
    //   construct.content.uses.removeWhere(
    //     (use) => use.constructType != constructType,
    //   );
    // }

    return constructEvents;
  }

  /// Get all the construct analytics events for the members of a space, of the specified type
  /// since the current timespan's cut off date, in the current language
  Future<List<ConstructAnalyticsEvent>> allSpaceMemberConstructs(
    Room room,
    ConstructTypeEnum constructType,
    TimeSpan timeSpan,
  ) async {
    final List<ConstructAnalyticsEvent> memberEvents =
        await allRoomMemberConstructs(room, constructType, timeSpan);

    final List<String> spaceChildrenIds = room.allSpaceChildRoomIds;
    final List<ConstructAnalyticsEvent> allConstructs = [];
    for (final constructEvent in memberEvents) {
      constructEvent.content.uses.removeWhere(
        (use) => !spaceChildrenIds.contains(use.chatId),
      );

      if (constructEvent.content.uses.isNotEmpty) {
        allConstructs.add(constructEvent);
      }
    }
    return allConstructs;
  }

  /// Filter out the construct analytics events that don't belong to the specified user
  List<ConstructAnalyticsEvent> filterStudentConstructs(
    List<ConstructAnalyticsEvent> unfilteredConstructs,
    String? studentId,
  ) {
    final List<ConstructAnalyticsEvent> filtered =
        List<ConstructAnalyticsEvent>.from(unfilteredConstructs);
    filtered.removeWhere((element) => element.event.senderId != studentId);
    return filtered;
  }

  /// Filter out the construct analytics events that don't belong to the specified room
  List<ConstructAnalyticsEvent> filterRoomConstructs(
    List<ConstructAnalyticsEvent> unfilteredConstructs,
    String? roomID,
  ) {
    final List<ConstructAnalyticsEvent> filtered = [...unfilteredConstructs];
    for (final construct in filtered) {
      construct.content.uses.removeWhere((u) => u.chatId != roomID);
    }
    return filtered;
  }

  /// Filter out the construct analytics events that don't
  /// belong to the specified space's private chats
  Future<List<ConstructAnalyticsEvent>> filterPrivateChatConstructs(
    List<ConstructAnalyticsEvent> unfilteredConstructs,
    Room space,
  ) async {
    final List<String> privateChatIds = space.allSpaceChildRoomIds;
    final List<String> lastFetched = getLatestSpaceHierarchy(space.id)
            ?.rooms
            .map((room) => room.roomId)
            .toList() ??
        [];
    for (final id in lastFetched) {
      privateChatIds.removeWhere((e) => e == id);
    }
    final List<ConstructAnalyticsEvent> filtered =
        List<ConstructAnalyticsEvent>.from(unfilteredConstructs);
    for (final construct in filtered) {
      construct.content.uses.removeWhere(
        (use) => !privateChatIds.contains(use.chatId),
      );
    }
    return filtered;
  }

  /// Filter out the construct analytics events that don't belong to the specified space
  Future<List<ConstructAnalyticsEvent>> filterSpaceConstructs(
    List<ConstructAnalyticsEvent> unfilteredConstructs,
    Room space,
  ) async {
    final List<String> chatIds = space.allSpaceChildRoomIds;
    final List<ConstructAnalyticsEvent> filtered =
        List<ConstructAnalyticsEvent>.from(unfilteredConstructs);

    for (final construct in filtered) {
      construct.content.uses.removeWhere(
        (use) => !chatIds.contains(use.chatId),
      );
    }

    return filtered;
  }

  /// Get the cached construct analytics events for the current timespan, type, and filters
  List<ConstructAnalyticsEvent>? getConstructsLocal({
    required TimeSpan timeSpan,
    required ConstructTypeEnum constructType,
    required AnalyticsSelected defaultSelected,
    AnalyticsSelected? selected,
    DateTime? lastUpdated,
  }) {
    final index = _cachedConstructs.indexWhere(
      (e) =>
          e.timeSpan == timeSpan &&
          e.type == constructType &&
          e.defaultSelected.id == defaultSelected.id &&
          e.defaultSelected.type == defaultSelected.type &&
          e.selected?.id == selected?.id &&
          e.selected?.type == selected?.type &&
          e.langCode == currentAnalyticsLang.langCode,
    );

    if (index > -1) {
      if (_cachedConstructs[index].needsUpdate(lastUpdated)) {
        _cachedConstructs.removeAt(index);
        return null;
      }
      return _cachedConstructs[index].events;
    }

    return null;
  }

  /// Cache the construct analytics events for the current timespan, type, and filters
  void cacheConstructs({
    required ConstructTypeEnum constructType,
    required List<ConstructAnalyticsEvent> events,
    required AnalyticsSelected defaultSelected,
    required TimeSpan timeSpan,
    AnalyticsSelected? selected,
  }) {
    final entry = ConstructCacheEntry(
      timeSpan: timeSpan,
      type: constructType,
      events: List.from(events),
      defaultSelected: defaultSelected,
      selected: selected,
      langCode: currentAnalyticsLang.langCode,
    );
    _cachedConstructs.add(entry);
  }

  Future<List<ConstructAnalyticsEvent>> filterConstructs({
    required List<ConstructAnalyticsEvent> unfilteredConstructs,
    required AnalyticsSelected defaultSelected,
    required ConstructTypeEnum constructType,
    required TimeSpan timeSpan,
    Room? space,
    AnalyticsSelected? selected,
  }) async {
    if ([AnalyticsEntryType.privateChats, AnalyticsEntryType.space]
        .contains(selected?.type)) {
      assert(space != null);
    }

    for (int i = 0; i < unfilteredConstructs.length; i++) {
      final construct = unfilteredConstructs[i];
      construct.content.uses.removeWhere(
        (use) =>
            use.timeStamp.isBefore(timeSpan.cutOffDate) ||
            use.constructType != constructType,
      );
    }

    unfilteredConstructs.removeWhere((e) => e.content.uses.isEmpty);

    switch (selected?.type) {
      case null:
        return unfilteredConstructs;
      case AnalyticsEntryType.student:
        if (defaultSelected.type != AnalyticsEntryType.space) {
          throw Exception(
            "student filtering not available for default filter ${defaultSelected.type}",
          );
        }
        return filterStudentConstructs(unfilteredConstructs, selected!.id);
      case AnalyticsEntryType.room:
        return filterRoomConstructs(unfilteredConstructs, selected?.id);
      case AnalyticsEntryType.privateChats:
        return defaultSelected.type == AnalyticsEntryType.student
            ? throw "private chat filtering not available for user analytics"
            : await filterPrivateChatConstructs(unfilteredConstructs, space!);
      case AnalyticsEntryType.space:
        return await filterSpaceConstructs(unfilteredConstructs, space!);
      default:
        throw Exception("invalid filter type - ${selected?.type}");
    }
  }

  Future<List<ConstructAnalyticsEvent>?> getConstructsById({
    required ConstructTypeEnum constructType,
    required String id,
    required AnalyticsEntryType type,
    TimeSpan? timeSpan,
  }) async {
    return await getConstructs(
      constructType: constructType,
      defaultSelected: AnalyticsSelected(id, type, ''),
      timeSpan: timeSpan,
    );
  }

  /// Given a construct type and a set of filters, get a list of
  /// construct analytics events.
  Future<List<ConstructAnalyticsEvent>?> getConstructs({
    required ConstructTypeEnum constructType,
    required AnalyticsSelected defaultSelected,
    TimeSpan? timeSpan,
    AnalyticsSelected? selected,
    bool removeIT = true,
    bool forceUpdate = false,
  }) async {
    debugPrint("getting constructs");
    await _pangeaController.matrixState.client.roomsLoading;
    timeSpan ??= currentAnalyticsTimeSpan;

    // if getting analytics for a set of participants in a room (that is,
    // if the primary filter is a space or a room), get the room and load
    // all of its state events and participants
    Room? room;
    if (defaultSelected.type == AnalyticsEntryType.space ||
        defaultSelected.type == AnalyticsEntryType.room) {
      room = _pangeaController.matrixState.client.getRoomById(
        defaultSelected.id,
      );

      // reasoning of this call to postLoad is that the room's power level
      // events are needed to determine which users are admins
      await room?.postLoad();

      // need the full participant list to get overall last updated time
      // and to determine who we need analytics rooms for
      await room?.requestParticipants();
    }

    // get the overall last updated time for the selected filter
    // this is used to determine if the cache is out-of-date
    DateTime? lastUpdated;
    switch (defaultSelected.type) {
      case AnalyticsEntryType.student:
        lastUpdated = await userAnalyticsLastUpdated(
          PangeaEventTypes.construct,
          userID: defaultSelected.id,
        );
        break;
      case AnalyticsEntryType.room:
      case AnalyticsEntryType.space:
        lastUpdated = await participantAnalyticsLastUpdated(
          PangeaEventTypes.construct,
          room!,
        );
        break;
      default:
        throw Exception(
          "invalid defaultSelected type - ${defaultSelected.type}",
        );
    }

    // get the cached constructs for this type, timespan, and set
    // of filters, if it exists and is still valid
    final List<ConstructAnalyticsEvent>? local = getConstructsLocal(
      timeSpan: timeSpan,
      constructType: constructType,
      defaultSelected: defaultSelected,
      selected: selected,
      lastUpdated: lastUpdated,
    );
    if (local != null && !forceUpdate) {
      debugPrint("returning local constructs");
      return local;
    }

    debugPrint("fetching new constructs");
    List<ConstructAnalyticsEvent> unfilteredConstructs;
    switch (defaultSelected.type) {
      case AnalyticsEntryType.student:
        unfilteredConstructs = await allUserConstructs(
          userID: defaultSelected.id,
          constructType: constructType,
          timeSpan: timeSpan,
        );
        break;
      case AnalyticsEntryType.room:
        unfilteredConstructs = await allRoomMemberConstructs(
          room!,
          constructType,
          timeSpan,
        );
        break;
      case AnalyticsEntryType.space:
        unfilteredConstructs = await allSpaceMemberConstructs(
          room!,
          constructType,
          timeSpan,
        );
        break;
      default:
        throw Exception(
          "invalid defaultSelected type - ${defaultSelected.type}",
        );
    }

    if (removeIT) {
      for (final construct in unfilteredConstructs) {
        construct.content.uses.removeWhere(
          (element) =>
              element.lemma == "Try interactive translation" ||
              element.lemma == "itStart" ||
              element.lemma == MatchRuleIds.interactiveTranslation,
        );
      }
    }

    final Room? selctedSpace = selected?.type == AnalyticsEntryType.space
        ? _pangeaController.matrixState.client.getRoomById(selected!.id)
        : null;

    final List<ConstructAnalyticsEvent> filteredConstructs =
        await filterConstructs(
      unfilteredConstructs: unfilteredConstructs,
      defaultSelected: defaultSelected,
      constructType: constructType,
      space: selctedSpace,
      selected: selected,
      timeSpan: timeSpan,
    );

    if (local == null) {
      cacheConstructs(
        constructType: constructType,
        events: filteredConstructs,
        defaultSelected: defaultSelected,
        selected: selected,
        timeSpan: timeSpan,
      );
    }

    return filteredConstructs;
  }
}

abstract class CacheEntry {
  final String langCode;
  final TimeSpan timeSpan;
  final AnalyticsSelected defaultSelected;
  AnalyticsSelected? selected;
  late final DateTime _createdAt;

  CacheEntry({
    required this.timeSpan,
    required this.defaultSelected,
    required this.langCode,
    this.selected,
  }) {
    _createdAt = DateTime.now();
  }

  bool get isExpired =>
      DateTime.now().difference(_createdAt).inMinutes >
      ClassDefaultValues.minutesDelayToMakeNewChartAnalytics;

  bool needsUpdate(DateTime? lastEventUpdated) {
    // cache entry is invalid if it's older than the last event update
    // if lastEventUpdated is null, that would indicate that no events
    // of this type have been sent to the room. In this case, there
    // shouldn't be any cached data.
    if (lastEventUpdated == null) {
      Sentry.addBreadcrumb(
        Breadcrumb(message: "lastEventUpdated is null in needsUpdate"),
      );
      return false;
    }
    return _createdAt.isBefore(lastEventUpdated);
  }
}

class ConstructCacheEntry extends CacheEntry {
  final ConstructTypeEnum type;
  final List<ConstructAnalyticsEvent> events;

  ConstructCacheEntry({
    required this.type,
    required this.events,
    required super.timeSpan,
    required super.langCode,
    required super.defaultSelected,
    super.selected,
  });
}

class AnalyticsCacheModel extends CacheEntry {
  final ChartAnalyticsModel chartAnalyticsModel;

  AnalyticsCacheModel({
    required this.chartAnalyticsModel,
    required super.timeSpan,
    required super.langCode,
    required super.defaultSelected,
    super.selected,
  });

  @override
  bool get isExpired =>
      DateTime.now().difference(_createdAt).inMinutes >
      ClassDefaultValues.minutesDelayToMakeNewChartAnalytics;
}
