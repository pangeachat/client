import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Whether the session counts as started: finished sessions always are;
/// otherwise every role in the plan is filled. With no plan (not yet hydrated,
/// or the activity was removed from the backend), the seat math would read
/// `0 - assigned <= 0` and misclassify every room as started — routing empty
/// orphan rooms into the chat timeline instead of the start page. Instead, a
/// plan-less room counts as started only when it has assigned roles (real
/// progress worth showing in the timeline).
@visibleForTesting
bool activityStartedGate({
  required bool finished,
  required int? planRoleCount,
  required int assignedRoleCount,
}) {
  if (finished) return true;
  if (planRoleCount == null) return assignedRoleCount > 0;
  return planRoleCount - assignedRoleCount <= 0;
}

class RoleException implements Exception {
  final String message;
  RoleException(this.message);

  @override
  String toString() => "RoleException: $message";
}

/// Whether a seat's holder has provably left the room. A role written in the
/// activity-role state event stays assigned unless a LOADED m.room.member
/// event says its holder left; `membership` is null when that event is not
/// loaded, which must count as still occupied (#7556): under lazy member
/// loading the holder — typically the bot — is routinely absent from the
/// loaded member list right after an invite refreshes it, and treating
/// "unknown" as "gone" made the bot's seat evaporate ("Waiting to fill 1
/// roles") and let the invitee overwrite it.
@visibleForTesting
bool roleHolderVacated(String? membership) =>
    membership == 'leave' || membership == 'ban';

@visibleForTesting
Map<String, ActivityRoleModel> filterAssignedRoles(
  Map<String, ActivityRoleModel> roles,
  String? Function(String userId) membershipOf,
) => Map.fromEntries(
  roles.entries.where((r) => !roleHolderVacated(membershipOf(r.value.userId))),
);

/// Whether [roles]' seat count is resting on the [roleHolderVacated] fallback
/// instead of on evidence: at least one holder has no LOADED `m.room.member`
/// event ([membershipOf] returns null), so its seat counts as occupied only
/// because nothing proves otherwise.
///
/// Member events never ride the SDK's preloaded-state path — they live in
/// their own store and come back into room state only through
/// [Room.requestParticipants] — so this is true for every session room the
/// learner hasn't opened this app session. The world map uses it to pick the
/// rooms worth a member refill before trusting their seats (#8045).
@visibleForTesting
bool hasUnresolvedSeatEvidence(
  Map<String, ActivityRoleModel>? roles,
  String? Function(String userId) membershipOf,
) => roles != null && roles.values.any((r) => membershipOf(r.userId) == null);

/// Claim guard for [ActivityRolesRoomExtension.joinActivity], keyed by role
/// ID: `updateRole` overwrites by id, so the guard must match on the same key
/// (the old name-based check on the membership-filtered map let a claim on an
/// occupied id slip through and overwrite the holder's entry).
@visibleForTesting
void guardSeatClaim({
  required String claimantId,
  required ActivityRoleModel? holder,
  required bool holderVacated,
  required bool claimantHoldsSeat,
}) {
  if (holder != null && holder.userId != claimantId && !holderVacated) {
    throw RoleException("Role already taken");
  }
  if (claimantHoldsSeat) {
    throw RoleException("User already has a role");
  }
}

extension ActivityRolesRoomExtension on Room {
  ActivityRolesModel? get activityRoles {
    final content = getState(PangeaEventTypes.activityRole)?.content;
    if (content == null) return null;

    try {
      return ActivityRolesModel.fromJson(content);
    } catch (e, s) {
      if (!kDebugMode && !Environment.isStagingEnvironment) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {"roomID": id, "stateEvent": content},
        );
      }
      return null;
    }
  }

  ActivityRoleModel? get ownRoleState => activityRoles?.role(client.userID!);

  ActivityRole? get ownRole {
    final role = ownRoleState;
    if (role == null || activityPlan == null) return null;

    return activityPlan!.roles[role.id];
  }

  int get numRemainingRoles {
    final availableRoles = activityPlan?.roles;
    return max(0, (availableRoles?.length ?? 0) - (assignedRoles?.length ?? 0));
  }

  bool get isActivityStarted => activityStartedGate(
    finished: isActivityFinished,
    planRoleCount: activityPlan?.roles.length,
    assignedRoleCount: assignedRoles?.length ?? 0,
  );

  bool get isActivityFinished {
    final roles = activityRoles?.roles.values.where(
      (r) => r.userId != BotName.byEnvironment,
    );

    if (roles == null || roles.isEmpty) return false;
    if (!roles.any((r) => r.isFinished)) return false;

    return roles.every((r) {
      if (r.isFinished) return true;

      // if the user is in the chat (not null && membership is join),
      // then the activity is not finished for them
      final user = getParticipants().firstWhereOrNull((u) => u.id == r.userId);
      return user == null || user.membership != Membership.join;
    });
  }

  bool get hasPickedRole => ownRoleState != null;

  bool get hasCompletedRole => ownRoleState?.isFinished ?? false;

  bool get hasArchivedActivity => ownRoleState?.isArchived ?? false;

  bool get isActiveInActivity => hasPickedRole && !hasCompletedRole;

  /// The Chats-list mirror of the map's `ongoingActive` pin state: the learner
  /// holds a seat, every seat is filled so the chat has really started, and
  /// their own role is neither finished nor archived. Split on the same
  /// discriminator the map uses — [numRemainingRoles] > 0 is Waiting (pending),
  /// 0 is active — over the same seat-held / own-role-live terms its session
  /// facts carry, so a session's tile and its large card can never disagree on
  /// when it is live (world-map.instructions.md, "Goal Progress").
  bool get isOngoingActiveSession =>
      isActiveInActivity && !hasArchivedActivity && numRemainingRoles == 0;

  /// Loaded membership of [userId] via [getParticipants] with the full
  /// membership filter — the DEFAULT filter drops leave/ban members, which is
  /// exactly the evidence [roleHolderVacated] needs. Null when the member
  /// event isn't loaded (lazy loading), which counts as still occupied.
  String? _membershipOf(String userId) => getParticipants(
    Membership.values,
  ).firstWhereOrNull((u) => u.id == userId)?.membership.name;

  Map<String, ActivityRoleModel>? get assignedRoles {
    final roles = activityRoles?.roles;
    if (roles == null) return null;
    return filterAssignedRoles(roles, _membershipOf);
  }

  /// True when this session's seat math is resting on unloaded member state —
  /// see [hasUnresolvedSeatEvidence]. Cheap: reads the loaded member list, never
  /// fetches. It flags the room for the world map's member-refill sweep
  /// (`WorldMapPinsManager.loadSessionParticipants`).
  bool get hasUnresolvedSeats =>
      hasUnresolvedSeatEvidence(activityRoles?.roles, _membershipOf);

  Future<void> joinActivity(ActivityRole role) async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    final holder = currentRoles.roles[role.id];
    guardSeatClaim(
      claimantId: client.userID!,
      holder: holder,
      holderVacated:
          holder != null && roleHolderVacated(_membershipOf(holder.userId)),
      claimantHoldsSeat: currentRoles.roles.values.any(
        (r) =>
            r.userId == client.userID &&
            !roleHolderVacated(_membershipOf(r.userId)),
      ),
    );

    final activityRole = ActivityRoleModel(
      id: role.id,
      userId: client.userID!,
      role: role.name,
    );

    currentRoles.updateRole(activityRole);
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }

  Future<void> continueActivity() async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    final role = ownRoleState;
    if (role == null || !role.isFinished) return;

    role.finishedAt = null; // Reset finished state
    currentRoles.updateRole(role);
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }

  Future<void> finishActivity() async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    final role = ownRoleState;
    if (role == null || role.isFinished) return;
    role.finishedAt = DateTime.now();
    currentRoles.updateRole(role);

    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }

  Future<void> finishActivityForAll() async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    currentRoles.finishAll();
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }

  /// Archives this user's finished role and returns the canonical archived-at
  /// marker it persisted — the SAME value the room state carries once the write
  /// syncs back, so a caller gets it WITHOUT racing `/sync` (reading
  /// `ownRoleState.archivedAt` right after this races the sync echo and can read
  /// null). Returns the existing archived-at when the role is already archived
  /// (no re-write), or null when there is no finished role to archive.
  ///
  /// [at] re-persists an archived-at this client already banked instead of
  /// stamping a fresh one. Every role lives in ONE shared state event, so
  /// archiving is a read-modify-write of the whole role map and a co-player
  /// archiving from a stale read drops this user's `archived_at` (#8258). The
  /// re-write that repairs that must replay the original instant, or the room
  /// would end up disagreeing with the dosage outcome already emitted against
  /// it.
  Future<DateTime?> archiveActivity({DateTime? at}) async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    final role = ownRoleState;
    if (role == null || !role.isFinished) return null;
    if (role.isArchived) return role.archivedAt;

    // UTC so the persisted archived_at (and the dosage completed_at derived from
    // it) is an unambiguous instant with an offset, never a bare local
    // wall-clock the server would have to guess a zone for.
    final archivedAt = at ?? DateTime.now().toUtc();
    role.archivedAt = archivedAt;
    currentRoles.updateRole(role);
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
    return archivedAt;
  }
}
