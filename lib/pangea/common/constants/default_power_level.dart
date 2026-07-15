import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

class RoomDefaults {
  /// [botUserId] (with the creator's [ownUserId]) seeds the bot at PL 50 so it
  /// can write its state events (e.g. pangea.orchestrator_awarded_goals,
  /// state_default 50) without the doomed self-promotion dance that overloaded
  /// staging Synapse (pangea-bot#1409). Synapse applies
  /// power_level_content_override as a SHALLOW top-level merge over its
  /// generated content (users: {creator: 100}); supplying "users" replaces
  /// that map, so the creator MUST be re-included or the room is created with
  /// a powerless creator and createRoom fails.
  ///
  /// KNOWN LIMITATION (dormant): room v12+/MSC4289 forbids listing the room
  /// CREATOR in users — if the homeserver default room version moves to v12,
  /// this map must become version-conditional (bot-only on v12). Synapse
  /// currently defaults to v10.
  static Map<String, dynamic> defaultPowerLevelsContent({
    String? ownUserId,
    String? botUserId,
  }) {
    // Half-specified grants are a silent footgun: {bot: 50} alone would wipe
    // the creator's 100 (shallow merge), and omitting the map leaves the bot
    // at PL 0 — fail loudly instead.
    assert(
      (ownUserId == null) == (botUserId == null),
      'ownUserId and botUserId must be passed together or not at all',
    );
    return {
      "ban": 50,
      "kick": 50,
      "invite": 50,
      "redact": 50,
      "events": {
        PangeaEventTypes.activityPlan: 0,
        PangeaEventTypes.activityRole: 0,
        PangeaEventTypes.activitySummary: 0,
        "m.room.power_levels": SpaceConstants.powerLevelOfAdmin,
        "m.room.pinned_events": 50,
      },
      "events_default": 0,
      "state_default": 50,
      "users_default": 0,
      "notifications": {"room": 50},
      if (botUserId != null && ownUserId != null)
        "users": {ownUserId: SpaceConstants.powerLevelOfAdmin, botUserId: 50},
    };
  }

  static Map<String, dynamic> get restrictedPowerLevelsContent => {
    "ban": 50,
    "kick": 50,
    "invite": 50,
    "redact": 50,
    "events": {
      PangeaEventTypes.activityPlan: 50,
      PangeaEventTypes.activityRole: 0,
      PangeaEventTypes.activitySummary: 0,
      "m.room.power_levels": 100,
      "m.room.pinned_events": 50,
    },
    "events_default": 50,
    "state_default": 50,
    "users_default": 0,
    "notifications": {"room": 50},
  };

  static Map<String, dynamic> defaultSpacePowerLevelsContent({
    int spaceChild = 50,
  }) => {
    "ban": 50,
    "kick": 50,
    "invite": 50,
    "redact": 50,
    "events": {
      "m.room.power_levels": 100,
      "m.room.join_rules": 100,
      "m.space.child": spaceChild,
    },
    "events_default": 0,
    "state_default": 50,
    "users_default": 0,
    "notifications": {"room": 50},
  };
}
