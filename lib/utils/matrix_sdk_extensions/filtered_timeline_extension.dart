import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import '../../config/app_config.dart';

extension VisibleInGuiExtension on List<Event> {
  List<Event> filterByVisibleInGui({String? exceptionEventId}) => where(
        // #Pangea
        // (event) => event.isVisibleInGui || event.eventId == exceptionEventId,
        (event) =>
            (event.isVisibleInGui || event.eventId == exceptionEventId) &&
            event.isVisibleInPangeaGui,
        // Pangea#
      ).toList();
}

extension IsStateExtension on Event {
  bool get isVisibleInGui =>
      // always filter out edit and reaction relationships
      !{RelationshipTypes.edit, RelationshipTypes.reaction}
          .contains(relationshipType) &&
      // always filter out m.key.* events
      !type.startsWith('m.key.verification.') &&
      // event types to hide: redaction and reaction events
      // if a reaction has been redacted we also want it to be hidden in the timeline
      !{EventTypes.Reaction, EventTypes.Redaction}.contains(type) &&
      // if we enabled to hide all redacted events, don't show those
      (!AppConfig.hideRedactedEvents || !redacted) &&
      // if we enabled to hide all unknown events, don't show those
      // #Pangea
      // (!AppConfig.hideUnknownEvents || isEventTypeKnown);
      (!AppConfig.hideUnknownEvents || pangeaIsEventTypeKnown) &&
      (!isState || importantStateEvents.contains(type)) &&
      content.tryGet(ModelKey.transcription) == null &&
      // if sending of transcription fails,
      // don't show it as a errored audio event in timeline.
      ((unsigned?['extra_content']
              as Map<String, dynamic>?)?[ModelKey.transcription] ==
          null);
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

  static const Set<String> importantStateEvents = {
    EventTypes.Encryption,
    EventTypes.RoomCreate,
    EventTypes.RoomMember,
    EventTypes.RoomTombstone,
    EventTypes.CallInvite,
    PangeaEventTypes.activityPlan,
    PangeaEventTypes.activityRole,
  };
  // Pangea#
}
