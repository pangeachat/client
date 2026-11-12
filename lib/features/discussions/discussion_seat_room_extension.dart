import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/discussions/discussion_room_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Ending and reopening the learner's own seat in a discussion, which
/// [ActivityRolesRoomExtension.finishActivity] and
/// [ActivityRolesRoomExtension.continueActivity] hand a discussion room to.
extension DiscussionSeatRoomExtension on Room {
  /// "I'm done" ([ended]) or "Wait, I'm not done" in a discussion. The server
  /// writes the seat (`finished_at` and `archived_at` together), so another
  /// student's seat can never be lost to a stale copy. Its leaving Chats
  /// follows from the archived seat ([isHiddenRoom]).
  ///
  /// The room is muted while the seat is ended, and gets back the learner's
  /// own setting from before it ended once they are back, so a learner who had
  /// muted it stays muted. A failed change of the notifications is captured,
  /// the seat's change is undone, and the failure goes to the caller's dialog,
  /// so the room is left as it was and the learner can tap again.
  Future<void> setOwnSeatEnded(bool ended) async {
    if (ownRoleState == null) {
      ErrorHandler.logError(
        e: StateError('No own seat to ${ended ? 'end' : 'continue'}'),
        data: {'roomId': id},
        level: SentryLevel.warning,
      );
      return;
    }
    final PushRuleState next;
    if (ended) {
      try {
        await _recordPushRuleBeforeEnd(pushRuleState);
      } catch (e, s) {
        ErrorHandler.logError(e: e, s: s, data: {'roomId': id});
        rethrow;
      }
      next = PushRuleState.dontNotify;
    } else {
      next = _pushRuleBeforeEnd ?? PushRuleState.notify;
    }
    final result = await DiscussionRoomRepo.setSeatEnded(
      client,
      roomId: id,
      ended: ended,
    );
    if (result.isError) throw result.asError!.error;
    try {
      await setPushRuleState(next);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': id, 'ended': ended, 'pushRule': next.name},
      );
      // The repo captures a failed undo itself; the learner is shown the
      // notifications' failure, which is what went wrong.
      await DiscussionRoomRepo.setSeatEnded(client, roomId: id, ended: !ended);
      rethrow;
    }
  }

  static const String _pushRuleStateKey = 'state';

  Future<void> _recordPushRuleBeforeEnd(PushRuleState state) =>
      client.setAccountDataPerRoom(
        client.userID!,
        id,
        PangeaEventTypes.discussionPushRuleBeforeEnd,
        {_pushRuleStateKey: state.name},
      );

  /// What [_recordPushRuleBeforeEnd] kept; null when nothing was kept (a seat
  /// ended on an older build), which restores the default.
  PushRuleState? get _pushRuleBeforeEnd {
    final name = roomAccountData[PangeaEventTypes.discussionPushRuleBeforeEnd]
        ?.content[_pushRuleStateKey];
    return PushRuleState.values.firstWhereOrNull((s) => s.name == name);
  }
}
