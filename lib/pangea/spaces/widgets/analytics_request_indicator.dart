import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/space_analytics_requested_dialog.dart';
import 'package:fluffychat/utils/stream_extension.dart';
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
  StreamSubscription? _memberSubscription;

  AnalyticsRequestIndicatorState();

  @override
  void initState() {
    super.initState();
    _memberSubscription ??= widget.room.client.onSync.stream
        .where(_isMemberUpdate)
        .rateLimit(const Duration(seconds: 1))
        .listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _memberSubscription?.cancel();
    super.dispose();
  }

  bool _isMemberUpdate(SyncUpdate update) {
    if (update.rooms == null) return false;
    final join = update.rooms!.join;
    final leave = update.rooms!.leave;
    if (join == null && leave == null) return false;

    final analyticsRooms = widget.room.client.allMyAnalyticsRooms;
    final hasJoinUpdates = join?.entries.any(
      (e) =>
          analyticsRooms.any((r) => r.id == e.key) &&
          e.value.state?.any((s) => s.type == EventTypes.RoomMember) == true,
    );
    if (hasJoinUpdates == true) return true;

    return leave?.entries.any(
          (e) =>
              analyticsRooms.any((r) => r.id == e.key) &&
              e.value.state?.any((s) => s.type == EventTypes.RoomMember) ==
                  true,
        ) ??
        false;
  }

  Map<User, List<Room>> get _knockingAdmins {
    final admins =
        widget.room.getParticipants().where((u) => u.powerLevel >= 100);

    final knockingAdmins = <User, List<Room>>{};
    for (final analyticsRoom in widget.room.client.allMyAnalyticsRooms) {
      final knocking = analyticsRoom.getParticipants([Membership.knock]);
      if (knocking.isEmpty) continue;

      for (final admin in admins) {
        if (knocking.any((u) => u.id == admin.id)) {
          knockingAdmins.putIfAbsent(admin, () => []).add(analyticsRoom);
        }
      }
    }

    debugPrint("knockingAdmins: $knockingAdmins");
    return knockingAdmins;
  }

  Future<void> _onTap(BuildContext context) async {
    final resp = await showDialog(
      context: context,
      builder: (context) {
        return SpaceAnalyticsRequestedDialog(room: widget.room);
      },
    );

    if (resp is! bool) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        for (final entry in _knockingAdmins.entries) {
          final user = entry.key;
          final rooms = entry.value;

          final List<Future> futures = resp
              ? rooms.map((room) => room.invite(user.id)).toList()
              : rooms.map((room) => room.kick(user.id)).toList();

          await Future.wait(futures);
        }
      },
    );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: 1,
      itemBuilder: (context, i) {
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
      },
    );
  }
}
