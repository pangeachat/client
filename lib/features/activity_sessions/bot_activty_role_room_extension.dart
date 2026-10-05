import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
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

  Future<void> addBotToActivity() =>
      client.setRoomStateWithKey(id, PangeaEventTypes.botParticipant, "", {});
}
