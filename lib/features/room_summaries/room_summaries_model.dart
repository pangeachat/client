import 'package:fluffychat/features/room_summaries/activity_sessions_status_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';

class RoomSummariesModel {
  final Map<String, RoomSummaryResponse> _roomSummaries;
  RoomSummariesModel(this._roomSummaries);

  RoomSummaryResponse? getRoomSummary(String roomId) => _roomSummaries[roomId];
}

class ActivitySessionSummariesModel extends RoomSummariesModel {
  final String activityId;
  ActivitySessionSummariesModel(
    super._roomSummaries, {
    required this.activityId,
  });

  Map<String, RoomSummaryResponse> get _activityInstances =>
      Map<String, RoomSummaryResponse>.fromEntries(
        _roomSummaries.entries.where(
          (e) => e.value.isActivityInstance(activityId),
        ),
      );

  Set<String> get openSessions => _activityInstances.entries
      .where((e) => e.value.isActivityOpenToJoin)
      .map((e) => e.key)
      .toSet();

  ActivitySessionsStatusModel get activitySessionStatuses =>
      ActivitySessionsStatusModel(_activityInstances);

  /// This model with [previews] laid over it: a fresher read replaces the
  /// sessions it covers, and every session it leaves out keeps its last read.
  ActivitySessionSummariesModel withPreviews(
    Map<String, RoomSummaryResponse> previews,
  ) => ActivitySessionSummariesModel({
    ..._roomSummaries,
    ...previews,
  }, activityId: activityId);
}
