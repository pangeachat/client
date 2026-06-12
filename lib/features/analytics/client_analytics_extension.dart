import 'dart:developer';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_event.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_status_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension AnalyticsClientExtension on Client {
  /// Get all my analytics rooms
  List<Room> get allMyAnalyticsRooms =>
      rooms.where((e) => e.isAnalyticsRoomOfUser(userID!)).toList();

  /// Get the logged in user's analytics room matching
  /// a given langCode. If not present, create it.
  Future<Room?> getMyAnalyticsRoom(LanguageModel lang) async {
    if (prevBatch == null) await onSync.stream.first;

    final Room? analyticsRoom = ownAnalyticsRoomLocal(lang: lang);
    if (analyticsRoom != null) return analyticsRoom;
    return _makeAnalyticsRoom(lang);
  }

  List<Room> _analyticsRoomsLocal({
    required LanguageModel lang,
    required String userID,
  }) => rooms
      .where(
        (e) => e.isAnalyticsRoomOfUserForLanguage(userID: userID, lang: lang),
      )
      .toList();

  Room? _canonicalAnalyticsRoom({
    required LanguageModel lang,
    required String userID,
  }) {
    final analyticsRooms = _analyticsRoomsLocal(lang: lang, userID: userID);
    if (analyticsRooms.length <= 1) {
      return analyticsRooms.firstOrNull;
    }

    DateTime? oldestCreationDate;
    Room canonicalAnalyticsRoom = analyticsRooms.first;
    for (final analyticsRoom in analyticsRooms) {
      final roomCreationTimestamp = analyticsRoom.creationTimestamp;
      if (roomCreationTimestamp == null) continue;
      if (oldestCreationDate == null ||
          oldestCreationDate.isAfter(roomCreationTimestamp)) {
        oldestCreationDate = roomCreationTimestamp;
        canonicalAnalyticsRoom = analyticsRoom;
      }
    }
    return canonicalAnalyticsRoom;
  }

  /// Get local analytics room for a given langCode and userId.
  /// If user is invited to the room, joins the room.
  Room? analyticsRoomLocal({
    required LanguageModel lang,
    required String userID,
  }) {
    final Room? analyticsRoom = _canonicalAnalyticsRoom(
      lang: lang,
      userID: userID,
    );

    if (analyticsRoom != null &&
        analyticsRoom.membership == Membership.invite) {
      debugger(when: kDebugMode);
      analyticsRoom.join().onError(
        (error, stackTrace) => ErrorHandler.logError(
          e: error,
          s: stackTrace,
          data: {"langCode": lang.langCodeShort, "userID": userID},
        ),
      );
    }

    return analyticsRoom;
  }

  Room? ownAnalyticsRoomLocal({required LanguageModel lang}) {
    final userID = this.userID;
    if (userID == null) {
      ErrorHandler.logError(
        e: "userID null in myAnalyticsRoomLocal",
        data: {"requested_lang": lang.langCode},
      );
      return null;
    }

    return analyticsRoomLocal(lang: lang, userID: userID);
  }

  Room? get ownAnalyticsRoomLocalByL2 {
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) {
      ErrorHandler.logError(
        e: "User L2 null in myAnalyticsRoomLocalByL2",
        data: {"userID": userID},
      );
      return null;
    }
    return ownAnalyticsRoomLocal(lang: l2);
  }

  /// Creates an analytics room with the specified language code and returns the created room.
  /// Additionally, the room is added to the user's spaces and all teachers are invited to the room.
  ///
  /// If the room does not appear immediately after creation, this method waits for it to appear in sync.
  /// Returns the created [Room] object.
  Future<Room?> _makeAnalyticsRoom(LanguageModel lang) async {
    if (userID == null || userID == BotName.byEnvironment) {
      return null;
    }

    final String roomID = await createRoom(
      creationContent: {
        'type': PangeaRoomTypes.analytics,
        ModelKey.langCode: lang.langCodeShort,
      },
      name: "$userID ${lang.langCodeShort} Analytics",
      topic: "This room stores learning analytics for $userID.",
      preset: CreateRoomPreset.publicChat,
      visibility: Visibility.private,
      initialState: [
        StateEvent(
          type: EventTypes.RoomJoinRules,
          content: {ModelKey.joinRule: JoinRules.knock.name},
        ),
      ],
    );
    if (getRoomById(roomID) == null) {
      // Wait for room actually appears in sync
      await waitForRoomInSync(roomID, join: true);
    }

    addAnalyticsRoomsToSpaces();
    grantAnalyticsAccessByAnalyticsRoom(roomID, lang.langCodeShort);
    return getRoomById(roomID)!;
  }

  /// Update the join rules of all analytics rooms to 'knock'.
  Future<void> updateAnalyticsRoomJoinRules() async {
    if (prevBatch == null) await onSync.stream.first;
    if (userID == null || userID == BotName.byEnvironment) return;
    final Random random = Random();

    for (final analyticsRoom in allMyAnalyticsRooms) {
      if (!isLogged()) return;
      if (analyticsRoom.joinRules == JoinRules.knock) continue;

      await analyticsRoom.setJoinRules(JoinRules.knock);
      await Future.delayed(Duration(seconds: random.nextInt(10)));
    }
  }

  /// Space admins join analytics rooms in spaces via the space hierarchy,
  /// so other members of the space need to add their analytics rooms to the space.
  Future<void> addAnalyticsRoomsToSpaces() async {
    if (prevBatch == null) await onSync.stream.first;
    if (userID == null || userID == BotName.byEnvironment) return;
    final spaces = rooms
        .where((room) => room.isSpace && room.membership == Membership.join)
        .toList();

    final Random random = Random();
    for (final space in spaces) {
      if (userID == null || !space.canSendEvent(EventTypes.SpaceChild)) return;
      final List<Room> roomsNotAdded = allMyAnalyticsRooms.where((room) {
        return !space.spaceChildren.any((child) => child.roomId == room.id);
      }).toList();

      if (roomsNotAdded.isEmpty) continue;

      for (final analyticsRoom in roomsNotAdded) {
        if (userID == null) return;
        try {
          await space.setSpaceChild(analyticsRoom.id);
        } catch (e, s) {
          ErrorHandler.logError(
            e: e,
            s: s,
            data: {
              "spaceID": space.id,
              "analyticsRoomID": analyticsRoom.id,
              "userID": userID,
            },
          );
        }
      }

      // add a delay before checking the next space to prevent overloading the server
      final delay = random.nextInt(10);
      debugPrint(
        "added ${roomsNotAdded.length} rooms to space ${space.id}, delay: $delay",
      );
      await Future.delayed(Duration(seconds: delay));
    }
  }

  /// Check if sync update includes newly joined room. Used by the
  /// GetAnalyticsController to add analytics rooms to newly joined spaces.
  bool isJoinSpaceSyncUpdate(SyncUpdate update) {
    if (update.rooms?.join == null) return false;
    return update.rooms!.join!.values
        .where(
          (e) =>
              e.state != null &&
              e.state!.any(
                (e) =>
                    e.type == EventTypes.RoomCreate &&
                    e.content['type'] == 'm.space',
              ),
        )
        .isNotEmpty;
  }

  Future<PangeaMessageEvent?> getEventByConstructUse(
    OneConstructUse use,
  ) async {
    if (use.metadata.eventId == null || use.metadata.roomId == null) {
      return null;
    }

    // wait for all rooms to sync
    if (prevBatch == null) {
      await onSync.stream.first;
    }

    final room = getRoomById(use.metadata.roomId!);
    if (room == null) {
      Logs().i("Room not found for construct use ${use.toJson()}");
      return null;
    }

    try {
      final event = await room.getEventById(use.metadata.eventId!);
      if (event == null) {
        ErrorHandler.logError(
          e: "Event not found for construct use",
          level: SentryLevel.warning,
          data: use.toJson(),
        );
        return null;
      }

      final timeline = await room.getTimeline();
      return PangeaMessageEvent(
        event: event,
        timeline: timeline,
        ownMessage: event.senderId == userID,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "roomID": use.metadata.roomId,
          "eventID": use.metadata.eventId,
          "userID": userID,
        },
      );
      return null;
    }
  }

  Future<Room?> combineAnalyticsRooms(LanguageModel lang) async {
    final analyticsRooms = _analyticsRoomsLocal(lang: lang, userID: userID!);
    final canonicalAnalyticsRoom = _canonicalAnalyticsRoom(
      lang: lang,
      userID: userID!,
    );

    if (canonicalAnalyticsRoom == null || analyticsRooms.length <= 1) {
      return analyticsRooms.firstOrNull;
    }

    for (final analyticsRoom in analyticsRooms) {
      try {
        if (analyticsRoom.id == canonicalAnalyticsRoom.id) continue;
        final roomConstructEvents = await analyticsRoom.getAnalyticsEvents(
          userId: userID!,
        );

        final constructEvents =
            roomConstructEvents ?? <ConstructAnalyticsEvent>[];
        final allUses = constructEvents
            .map((e) => e.content.uses)
            .expand((u) => u)
            .toList();
        await canonicalAnalyticsRoom.sendConstructsEvent(allUses);

        final activityRoomIds = analyticsRoom.activityRoomIds.toSet();
        await canonicalAnalyticsRoom.addActivityRoomIds(activityRoomIds);

        await analyticsRoom.markAnalyticsRoomMerged();
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'analytics_room_id': analyticsRoom.id},
        );
      }
    }

    return canonicalAnalyticsRoom;
  }
}
