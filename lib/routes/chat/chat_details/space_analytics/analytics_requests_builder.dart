import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Loads and watches the course admins knocking on the user's analytics
/// rooms with [room] (the course) as the reason — the analytics-access
/// requests the Catch up section reviews — rebuilding [builder] as requests
/// arrive or get resolved (granted → invite, denied → kick).
class AnalyticsRequestsBuilder extends StatefulWidget {
  final Room room;
  final Widget Function(BuildContext context, Map<User, List<Room>> requests)
  builder;

  const AnalyticsRequestsBuilder({
    super.key,
    required this.room,
    required this.builder,
  });

  @override
  State<AnalyticsRequestsBuilder> createState() =>
      AnalyticsRequestsBuilderState();
}

class AnalyticsRequestsBuilderState extends State<AnalyticsRequestsBuilder> {
  StreamSubscription? _analyticsRoomSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant AnalyticsRequestsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _init();
    }
  }

  @override
  void dispose() {
    _analyticsRoomSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final analyticsRooms = widget.room.client.allMyAnalyticsRooms;
    // Subscribe FIRST, so a member update landing while the initial load is
    // in flight isn't missed — and so a failed initial load still leaves the
    // section live for later updates.
    final analyticsRoomIds = analyticsRooms.map((r) => r.id).toSet();
    _analyticsRoomSub?.cancel();
    _analyticsRoomSub = widget.room.client.onSync.stream.listen((update) async {
      final joined = update.rooms?.join?.entries.where(
        (e) => analyticsRoomIds.contains(e.key),
      );

      if (joined == null || joined.isEmpty) return;
      final Set<String> updatedRoomIds = {};
      for (final entry in joined) {
        final memberEvents = entry.value.timeline?.events?.where(
          (e) => e.type == EventTypes.RoomMember,
        );
        if (memberEvents != null && memberEvents.isNotEmpty) {
          updatedRoomIds.add(entry.key);
        }
      }

      if (updatedRoomIds.isEmpty) return;
      for (final roomId in updatedRoomIds) {
        final room = widget.room.client.getRoomById(roomId);
        if (room == null) continue;
        await room.requestParticipants(
          [Membership.join, Membership.invite, Membership.knock],
          false,
          true,
        );
      }

      if (mounted) {
        setState(() {});
      }
    });

    try {
      await Future.wait(
        analyticsRooms.map(
          (r) => r.requestParticipants(
            [Membership.join, Membership.invite, Membership.knock],
            false,
            true,
          ),
        ),
      );
    } catch (err, s) {
      // The subscription above still refreshes on the next member update;
      // log rather than let the initializer complete with an unhandled error.
      ErrorHandler.logError(e: err, s: s, data: {'roomId': widget.room.id});
    }
    if (mounted) setState(() {});
  }

  /// Each requesting admin, with the analytics rooms they knocked on citing
  /// this course. Grouped by user ID — `User ==` also compares room, so the
  /// same admin knocking several analytics rooms would otherwise be listed
  /// once per room; the first-seen `User` stands in for display and actions.
  Map<User, List<Room>> get requests {
    final Map<String, User> adminsById = {};
    final Map<String, List<Room>> roomsByAdminId = {};
    for (final analyticsRoom in widget.room.client.allMyAnalyticsRooms) {
      final knocking = analyticsRoom
          .getParticipants([Membership.knock])
          .where((u) => u.content['reason'] == widget.room.id);
      for (final admin in knocking) {
        adminsById.putIfAbsent(admin.id, () => admin);
        roomsByAdminId.putIfAbsent(admin.id, () => []).add(analyticsRoom);
      }
    }
    return {
      for (final entry in adminsById.entries)
        entry.value: roomsByAdminId[entry.key]!,
    };
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, requests);
}
