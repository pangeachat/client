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

extension BotActivtyRoleRoomExtension on Room {
  bool get botHasActivityRole => botHoldsLiveSeat(
    assignedRoles?.values ?? const [],
    BotName.byEnvironment,
  );

  Future<void> addBotToActivity() =>
      client.setRoomStateWithKey(id, PangeaEventTypes.botParticipant, "", {});
}
