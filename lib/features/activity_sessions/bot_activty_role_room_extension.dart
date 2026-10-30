import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Whether the bot occupies one of [assignedRoles] — the seats whose holders
/// have not provably left the room (see [filterAssignedRoles]). This, not the
/// pangea.bot_participant marker, is what "the bot is in the activity" means
/// for UI gates (#8099): the marker is sticky and outlives the bot leaving,
/// so gating on it left "Play with Pangea Bot" dead after the bot dropped out
/// of a session with its role unfilled.
@visibleForTesting
bool botHoldsLiveSeat(
  Iterable<ActivityRoleModel> assignedRoles,
  String botUserId,
) => assignedRoles.any((r) => r.userId == botUserId);

/// Whether this session is a learner alone with the bot: the activity has
/// exactly two roles and the bot holds one of them. The surfaces that only
/// make sense between people are dropped in that case — "End for all" (there
/// is nobody else to end it for) and starting a poll (the bot cannot vote in
/// one, so the poll would sit unanswered forever — #8982).
@visibleForTesting
bool isTwoPersonBotSession(
  int roleCount,
  Iterable<ActivityRoleModel> assignedRoles,
  String botUserId,
) => roleCount == 2 && botHoldsLiveSeat(assignedRoles, botUserId);

/// pangea-bot takes a waiting session's last open seat this long after the
/// session was created, and only in sessions younger than [botFillMaxAge]
/// (OPEN_SEAT_TIMEOUT_MS and MAX_SESSION_AGE_MS in its open-session sweep).
const botFillDelay = Duration(hours: 1);
const botFillMaxAge = Duration(days: 1);

/// Seats people hold, the way pangea-bot counts them: a role or an invite holds
/// one; a member who joined without a role, such as a course admin the
/// homeserver joined to read along, holds none. The bot's own seat is not
/// counted.
@visibleForTesting
int heldSeatCount({
  required Iterable<ActivityRoleModel> assignedRoles,
  required int invitedMembers,
  required bool botInvited,
  required String botUserId,
}) =>
    assignedRoles.where((r) => r.userId != botUserId).length +
    invitedMembers -
    (botInvited ? 1 : 0);

/// When pangea-bot will take a waiting session's last seat on its own, or null
/// when it won't (activity-start-page.instructions.md, "The waiting room"). The
/// bot's own rule: nobody has asked for it, the creator and the bot are in,
/// nothing has finished, and held seats ([heldSeatCount]) leave exactly one
/// open.
@visibleForTesting
DateTime? botFillTime({
  required DateTime created,
  required DateTime now,
  required bool botChosen,
  required bool creatorJoined,
  required bool botJoined,
  required bool anyRoleFinished,
  required int seats,
  required int takenSeats,
}) {
  if (botChosen || !creatorJoined || !botJoined || anyRoleFinished) {
    return null;
  }
  if (seats - takenSeats != 1 || now.difference(created) >= botFillMaxAge) {
    return null;
  }
  return created.add(botFillDelay);
}

extension BotActivtyRoleRoomExtension on Room {
  bool get botHasActivityRole => botHoldsLiveSeat(
    assignedRoles?.values ?? const [],
    BotName.byEnvironment,
  );

  bool get isTwoPersonBotActivity {
    final roles = activityRoles?.roles;
    if (roles == null) return false;
    return isTwoPersonBotSession(
      roles.length,
      assignedRoles?.values ?? const [],
      BotName.byEnvironment,
    );
  }

  /// See [botFillTime] and [heldSeatCount].
  DateTime? get botFillsOpenSeatAt {
    final create = getState(EventTypes.RoomCreate);
    final seats = activityPlan?.roles.length;
    if (create is! Event || seats == null) return null;
    String? membershipOf(String userId) => getState(
      EventTypes.RoomMember,
      userId,
    )?.content.tryGet<String>('membership');
    final botMembership = membershipOf(BotName.byEnvironment);
    return botFillTime(
      created: create.originServerTs,
      now: DateTime.now(),
      botChosen: getState(PangeaEventTypes.botParticipant) != null,
      creatorJoined: membershipOf(create.senderId) == Membership.join.name,
      botJoined: botMembership == Membership.join.name,
      anyRoleFinished:
          activityRoles?.roles.values.any((r) => r.isFinished) ?? false,
      seats: seats,
      takenSeats: heldSeatCount(
        assignedRoles: assignedRoles?.values ?? const [],
        invitedMembers: summary.mInvitedMemberCount ?? 0,
        botInvited: botMembership == Membership.invite.name,
        botUserId: BotName.byEnvironment,
      ),
    );
  }

  Future<void> addBotToActivity() =>
      client.setRoomStateWithKey(id, PangeaEventTypes.botParticipant, "", {});
}
