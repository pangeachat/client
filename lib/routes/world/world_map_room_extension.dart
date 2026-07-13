import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';

extension WorldMapRoomExtension on Room {
  List<LargeCardParticipant> get largeCardParticipants => getParticipants()
      .where(
        (u) => u.membership == Membership.join && u.id != BotName.byEnvironment,
      )
      .map<LargeCardParticipant>(
        (u) => (avatar: u.avatarUrl, name: u.calcDisplayname()),
      )
      .toList();
}

/// The large card's participant/seat source for a session the learner has NOT
/// joined — a coursemate's discovered session or an invite — where the accurate
/// data is the `room_preview` summary, never local (stripped) room state
/// (#7488). The preview carries member ids without profiles, so participants
/// render by localpart with no avatar image.
extension WorldMapSummaryExtension on RoomSummaryResponse {
  /// [botUserId] is injectable for tests only ([BotName.byEnvironment] reads
  /// env/storage that unit tests don't initialize); production callers omit it.
  List<LargeCardParticipant> largeCardParticipants({String? botUserId}) =>
      membershipSummary.entries
          .where(
            (e) =>
                e.value == Membership.join.name &&
                e.key != (botUserId ?? BotName.byEnvironment),
          )
          .map<LargeCardParticipant>(
            (e) => (avatar: null, name: e.key.localpart ?? e.key),
          )
          .toList();

  /// Free seats: the plan's role count minus seats verifiably taken (assigned
  /// AND joined). 0 when the preview carries only a thin plan ref (v3) — seat
  /// count unknown, so show nothing rather than phantoms.
  int get openSlots {
    final plan = activityPlan;
    if (plan == null) return 0;
    return max(0, plan.roles.length - joinedUsersWithRoles.length);
  }
}
