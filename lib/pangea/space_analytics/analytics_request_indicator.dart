import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/space_analytics/space_analytics_requested_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class AnalyticsRequestIndicator extends StatefulWidget {
  final Room room;
  const AnalyticsRequestIndicator({
    super.key,
    required this.room,
  });

  @override
  AnalyticsRequestIndicatorState createState() =>
      AnalyticsRequestIndicatorState();
}

class AnalyticsRequestIndicatorState extends State<AnalyticsRequestIndicator> {
  AnalyticsRequestIndicatorState();
  StreamSubscription? _analyticsRoomSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant AnalyticsRequestIndicator oldWidget) {
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
    final futures = analyticsRooms.map(
      (r) => r.requestParticipants(
        [Membership.join, Membership.invite, Membership.knock],
        false,
        true,
      ),
    );
    await Future.wait(futures);

    final analyticsRoomIds = analyticsRooms.map((r) => r.id).toSet();
    _analyticsRoomSub?.cancel();
    _analyticsRoomSub = widget.room.client.onSync.stream.listen((update) async {
      final joined = update.rooms?.join?.entries
          .where((e) => analyticsRoomIds.contains(e.key));

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
  }

  Map<User, List<Room>> get _knockingAdmins {
    final Map<User, List<Room>> knockingAdmins = {};
    for (final analyticsRoom in widget.room.client.allMyAnalyticsRooms) {
      final knocking = analyticsRoom
          .getParticipants([Membership.knock])
          .where((u) => u.content['reason'] == widget.room.id)
          .toList();

      if (knocking.isEmpty) continue;
      for (final admin in knocking) {
        knockingAdmins.putIfAbsent(admin, () => []).add(analyticsRoom);
      }
    }

    return knockingAdmins;
  }

  Future<void> _onTap(BuildContext context) async {
    final requestingUsers = _knockingAdmins.keys.toList();
    final resp = await showDialog(
      context: context,
      builder: (context) {
        return SpaceAnalyticsRequestedDialog(
          room: widget.room,
          requestingUsers: requestingUsers,
        );
      },
    );

    if (resp is! bool) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        for (final entry in _knockingAdmins.entries) {
          final user = entry.key;
          final rooms = entry.value;

          final List<Future> futures = rooms
              .map(
                (room) => resp
                    ? room.invite(
                        user.id,
                        reason: PangeaEventTypes.analyticsInviteContent,
                      )
                    : room.kick(user.id),
              )
              .toList();

          await Future.wait(futures);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      child: _knockingAdmins.isEmpty
          ? const SizedBox()
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 1,
              ),
              child: Material(
                borderRadius: BorderRadius.circular(
                  AppConfig.borderRadius,
                ),
                clipBehavior: Clip.hardEdge,
                child: ListTile(
                  minVerticalPadding: 0,
                  trailing: Icon(
                    Icons.arrow_right,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Row(
                    spacing: 8.0,
                    children: [
                      Icon(
                        Icons.notifications_active_outlined,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      Expanded(
                        child: Text(
                          L10n.of(context).adminRequestedAccess,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _onTap(context),
                ),
              ),
            ),
    );
  }
}
