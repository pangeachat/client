import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
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

  /// Both call sites (PangeaController) fire this without awaiting, so a
  /// failure has nowhere to go: on web it escapes to the browser's global
  /// handler and lands in Sentry raw — no severity table, no grouping key
  /// (CLIENT-EHD,
  /// an expired token failing `setPushRule`). Reported here through the one
  /// sink instead; the rules are re-attempted on the next login or analytics
  /// room, so there is nothing else for a caller to do with the failure.
  Future<void> setPangeaPushRules() async {
    try {
      await _setPangeaPushRules();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    }
  }

  Future<void> _setPangeaPushRules() async {
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

    // A call notification must ring, not read like a mention. Without a rule of
    // its own, an MSC4075 event rides the generic mention rule — Synapse ships
    // nothing for it — so it would push with the default sound instead of a
    // ring, and a backgrounded phone would chime rather than ring.
    //
    // Set every time rather than only when missing: a rule left by an earlier
    // version with the wrong sound or conditions must be repaired, and the "skip
    // if present" pattern the other rules use would leave that broken forever.
    // This runs on login and account change, not a hot path, so the write is
    // cheap insurance.
    await setPushRule(
      PushRuleKind.override,
      PangeaEventTypes.callNotification,
      [
        PushRuleAction.notify,
        {'set_tweak': 'sound', 'value': 'ring'},
        {'set_tweak': 'highlight', 'value': false},
      ],
      conditions: [
        PushCondition(
          kind: 'event_match',
          key: 'type',
          pattern: PangeaEventTypes.callNotification,
        ),
        // Only an audible ring, not a quiet notice.
        PushCondition(
          kind: 'event_match',
          key: 'content.application.notification_type',
          pattern: 'ring',
        ),
      ],
    );
  }
}
