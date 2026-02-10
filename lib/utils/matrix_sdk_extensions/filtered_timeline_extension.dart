import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';

extension VisibleInGuiExtension on List<Event> {
  List<Event> filterByVisibleInGui({
    String? exceptionEventId,
    String? threadId,
  }) => where((event) {
    if (threadId != null &&
        event.relationshipType != RelationshipTypes.reaction) {
      if ((event.relationshipType != RelationshipTypes.thread ||
              event.relationshipEventId != threadId) &&
          event.eventId != threadId) {
        return false;
      }
    } else if (event.relationshipType == RelationshipTypes.thread) {
      return false;
    }
    // #Pangea
    // return event.isVisibleInGui || event.eventId == exceptionEventId;
    return (event.isVisibleInGui || event.eventId == exceptionEventId) &&
        event.isVisibleInPangeaGui;
    // Pangea#
  }).toList();
}

extension IsStateExtension on Event {
  bool get isVisibleInGui =>
      // always filter out edit and reaction relationships
      !{
        RelationshipTypes.edit,
        RelationshipTypes.reaction,
      }.contains(relationshipType) &&
      // always filter out m.key.* and other known but unimportant events
      !isKnownHiddenStates &&
      // event types to hide: redaction and reaction events
      // if a reaction has been redacted we also want it to be hidden in the timeline
      !{EventTypes.Reaction, EventTypes.Redaction}.contains(type) &&
      // if we enabled to hide all redacted events, don't show those
      (!AppSettings.hideRedactedEvents.value || !redacted) &&
      // if we enabled to hide all unknown events, don't show those
      // #Pangea
      // (!AppSettings.hideUnknownEvents.value || isEventTypeKnown);
      (!AppSettings.hideUnknownEvents.value || pangeaIsEventTypeKnown) &&
      content.tryGet(ModelKey.transcription) == null &&
      ((unsigned?['extra_content']
              as Map<String, dynamic>?)?[ModelKey.transcription] ==
          null) &&
      (!isState || importantStateEvents.contains(type));
  // Pangea#

  bool get isState => !{
    EventTypes.Message,
    EventTypes.Sticker,
    EventTypes.Encrypted,
  }.contains(type);

  bool get isCollapsedState => !{
    EventTypes.Message,
    EventTypes.Sticker,
    EventTypes.Encrypted,
    EventTypes.RoomCreate,
    EventTypes.RoomTombstone,
  }.contains(type);

  bool get isKnownHiddenStates =>
      {PollEventContent.responseType}.contains(type) ||
      type.startsWith('m.key.verification.');

  // #Pangea
  bool get isVisibleInPangeaGui {
    if (!room.showActivityChatUI) {
      return type != EventTypes.RoomMember ||
          (roomMemberChangeType != RoomMemberChangeType.avatar &&
              roomMemberChangeType != RoomMemberChangeType.other);
    }

    return type != EventTypes.RoomMember;
  }

  bool get pangeaIsEventTypeKnown =>
      isEventTypeKnown ||
      [
        PangeaEventTypes.activityPlan,
        PangeaEventTypes.activityRole,
      ].contains(type);

  // we're filtering out some state events that we don't want to render
  static const Set<String> importantStateEvents = {
    EventTypes.Encryption,
    EventTypes.RoomCreate,
    EventTypes.RoomMember,
    EventTypes.RoomTombstone,
    EventTypes.CallInvite,
    PollEventContent.startType,
    PangeaEventTypes.activityPlan,
    PangeaEventTypes.activityRole,
  };
  // Pangea#
}
