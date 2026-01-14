import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';

extension PangeaPushRulesExtension on Client {
  Future<void> setPangeaPushRules() async {
    if (!isLogged()) return;
    final List<Room> analyticsRooms =
        rooms.where((room) => room.isAnalyticsRoom).toList();

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
