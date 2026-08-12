import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

extension PangeaPushRulesExtension on Client {
  /// Whether this sync update contains an analytics room newly appearing as
  /// joined or invited. Rooms that appear mid-session need their dontNotify
  /// rule set then — [setPangeaPushRules] alone only covers rooms present at
  /// app start.
  bool isNewAnalyticsRoomSyncUpdate(SyncUpdate update) {
    bool isAnalyticsCreate(StrippedStateEvent event) =>
        event.type == EventTypes.RoomCreate &&
        event.content['type'] == PangeaRoomTypes.analytics;

    final joined =
        update.rooms?.join?.values.any(
          (room) => room.state?.any(isAnalyticsCreate) ?? false,
        ) ??
        false;
    final invited =
        update.rooms?.invite?.values.any(
          (room) => room.inviteState?.any(isAnalyticsCreate) ?? false,
        ) ??
        false;
    return joined || invited;
  }

  Future<void> setPangeaPushRules() async {
    if (!isLogged()) return;
    if (prevBatch == null) await onSync.stream.first;

    final List<Room> analyticsRooms = rooms
        .where((room) => room.isAnalyticsRoom)
        .toList();

    for (final Room room in analyticsRooms) {
      final pushRule = room.pushRuleState;
      if (pushRule != PushRuleState.dontNotify) {
        await room.setPushRuleState(PushRuleState.dontNotify);
      }
    }

    if (!(globalPushRules?.override?.any(
          (element) => element.ruleId == PangeaEventTypes.analyticsInviteRule,
        ) ??
        false)) {
      await setPushRule(
        PushRuleKind.override,
        PangeaEventTypes.analyticsInviteRule,
        [PushRuleAction.dontNotify],
        conditions: [
          PushCondition(
            kind: 'event_match',
            key: 'type',
            pattern: EventTypes.RoomMember,
          ),
          PushCondition(
            kind: 'event_match',
            key: 'content.reason',
            pattern: PangeaEventTypes.analyticsInviteContent,
          ),
        ],
      );
    }

    if (!(globalPushRules?.override?.any(
          (element) => element.ruleId == PangeaEventTypes.textToSpeechRule,
        ) ??
        false)) {
      await setPushRule(
        PushRuleKind.override,
        PangeaEventTypes.textToSpeechRule,
        [PushRuleAction.dontNotify],
        conditions: [
          PushCondition(
            kind: 'event_match',
            key: 'content.msgtype',
            pattern: MessageTypes.Audio,
          ),
          PushCondition(
            kind: 'event_match',
            key: 'content.transcription.lang_code',
            pattern: '*',
          ),
          PushCondition(
            kind: 'event_match',
            key: 'content.transcription.text',
            pattern: '*',
          ),
        ],
      );
    }
  }
}
