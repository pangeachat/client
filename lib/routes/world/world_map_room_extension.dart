import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';

extension WorldMapRoomExtension on Room {
  /// One filled circle per *role holder* — a user who currently holds a seat
  /// ([assignedRoles], which drops holders who provably left) — NOT every joined
  /// member. Ids only: the row fetches each holder's profile itself, so a seat
  /// still renders with a real name and avatar when the room has no loaded
  /// member event for its holder (#8192).
  List<String> get largeCardParticipantIds {
    final assigned = assignedRoles;
    if (assigned == null || assigned.isEmpty) return const [];
    return assigned.values.map((role) => role.userId).toList();
  }
}

/// The large card's participant/seat source for a session the learner has NOT
/// joined — a coursemate's discovered session or an invite — where the accurate
/// data is the `room_preview` summary, never local (stripped) room state
/// (#7488).
extension WorldMapSummaryExtension on RoomSummaryResponse {
  /// One filled circle per *joined role holder* ([joinedUsersWithRoles]) — like
  /// the live-room getter, only users who hold a seat, so the moderation bot
  /// shows only when it has a role. Pairs with [openSlots] (empty seats) for a
  /// total of the plan's role count.
  List<String> get largeCardParticipantIds =>
      joinedUsersWithRoles.values.map((role) => role.userId).toList();

  /// Free seats: the plan's role count minus seats verifiably taken (assigned
  /// AND joined). Thin v3 refs resolve through [resolvedActivityPlan]; 0 while
  /// the plan is still hydrating — seat count unknown, so show nothing rather
  /// than phantoms.
  int get openSlots {
    final plan = resolvedActivityPlan;
    if (plan == null) return 0;
    return max(0, plan.roles.length - joinedUsersWithRoles.length);
  }
}
