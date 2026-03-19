import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

class RoomDefaults {
  static Map<String, dynamic> get defaultPowerLevelsContent => {
    "ban": 50,
    "kick": 50,
    "invite": 50,
    "redact": 50,
    "events": {
      PangeaEventTypes.activityPlan: 0,
      PangeaEventTypes.activityRole: 0,
      PangeaEventTypes.activitySummary: 0,
      "m.room.power_levels": 100,
      "m.room.pinned_events": 50,
    },
    "events_default": 0,
    "state_default": 50,
    "users_default": 0,
    "notifications": {"room": 50},
  };

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
